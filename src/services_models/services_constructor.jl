function get_incompatible_devices(devices_template::Dict)
    incompatible_device_types = Set{DataType}()
    for model in values(devices_template)
        formulation = get_formulation(model)
        if formulation == FixedOutput
            if !isempty(get_services(model))
                @info "$(formulation) for $(get_component_type(model)) is not compatible with the provision of reserve services"
            end
            push!(incompatible_device_types, get_component_type(model))
        end
    end
    return incompatible_device_types
end

function construct_services!(
    container::OptimizationContainer,
    sys::PSY.System,
    stage::IS.ArgumentConstructStage,
    services_template::ServicesModelContainer,
    devices_template::DevicesModelContainer,
)
    isempty(services_template) && return
    incompatible_device_types = get_incompatible_devices(devices_template)

    groupservice = nothing

    for (key, service_model) in services_template
        if get_formulation(service_model) === GroupReserve  # group service needs to be constructed last
            groupservice = key
            continue
        end
        isempty(get_contributing_devices(service_model)) && continue
        construct_service!(
            container,
            sys,
            stage,
            service_model,
            devices_template,
            incompatible_device_types,
        )
    end
    groupservice === nothing || construct_service!(
        container,
        sys,
        stage,
        services_template[groupservice],
        devices_template,
        incompatible_device_types,
    )
    return
end

function construct_services!(
    container::OptimizationContainer,
    sys::PSY.System,
    stage::IS.ModelConstructStage,
    services_template::ServicesModelContainer,
    devices_template::DevicesModelContainer,
)
    isempty(services_template) && return
    incompatible_device_types = get_incompatible_devices(devices_template)

    groupservice = nothing
    for (key, service_model) in services_template
        if get_formulation(service_model) === GroupReserve  # group service needs to be constructed last
            groupservice = key
            continue
        end
        isempty(get_contributing_devices_map(service_model)) && continue
        construct_service!(
            container,
            sys,
            stage,
            service_model,
            devices_template,
            incompatible_device_types,
        )
    end
    groupservice === nothing || construct_service!(
        container,
        sys,
        stage,
        services_template[groupservice],
        devices_template,
        incompatible_device_types,
    )
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::IS.ArgumentConstructStage,
    model::ServiceModel{SR, RangeReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
) where {SR <: PSY.Reserve}
    name = get_service_name(model)
    service = PSY.get_component(SR, sys, name)
    add_parameters!(container, RequirementTimeSeriesParameter, service, model)
    contributing_devices = get_contributing_devices(model)

    add_variables!(
        container,
        ActivePowerReserveVariable,
        service,
        contributing_devices,
        RangeReserve(),
    )
    add_to_expression!(container, ActivePowerReserveVariable, model, devices_template)
    add_feedforward_arguments!(container, model, service)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::IS.ModelConstructStage,
    model::ServiceModel{SR, RangeReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
) where {SR <: PSY.Reserve}
    name = get_service_name(model)
    service = PSY.get_component(SR, sys, name)
    contributing_devices = get_contributing_devices(model)

    add_constraints!(container, RequirementConstraint, service, contributing_devices, model)
    add_constraints!(
        container,
        ParticipationFractionConstraint,
        service,
        contributing_devices,
        model,
    )
    objective_function!(container, service, model)

    add_feedforward_constraints!(container, model, service)

    add_constraint_dual!(container, sys, model)

    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::IS.ArgumentConstructStage,
    model::ServiceModel{SR, RangeReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
) where {SR <: PSY.StaticReserve}
    name = get_service_name(model)
    service = PSY.get_component(SR, sys, name)
    contributing_devices = get_contributing_devices(model)

    add_variables!(
        container,
        ActivePowerReserveVariable,
        service,
        contributing_devices,
        RangeReserve(),
    )
    add_to_expression!(container, ActivePowerReserveVariable, model, devices_template)
    add_feedforward_arguments!(container, model, service)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::IS.ModelConstructStage,
    model::ServiceModel{SR, RangeReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
) where {SR <: PSY.StaticReserve}
    name = get_service_name(model)
    service = PSY.get_component(SR, sys, name)
    contributing_devices = get_contributing_devices(model)

    add_constraints!(container, RequirementConstraint, service, contributing_devices, model)
    add_constraints!(
        container,
        ParticipationFractionConstraint,
        service,
        contributing_devices,
        model,
    )
    objective_function!(container, service, model)

    add_feedforward_constraints!(container, model, service)

    add_constraint_dual!(container, sys, model)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::IS.ArgumentConstructStage,
    model::ServiceModel{SR, StepwiseCostReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
) where {SR <: PSY.Reserve}
    name = get_service_name(model)
    service = PSY.get_component(SR, sys, name)
    contributing_devices = get_contributing_devices(model)
    add_variable!(container, ServiceRequirementVariable(), [service], StepwiseCostReserve())
    add_variables!(
        container,
        ActivePowerReserveVariable,
        service,
        contributing_devices,
        StepwiseCostReserve(),
    )
    add_to_expression!(container, ActivePowerReserveVariable, model, devices_template)
    add_expressions!(container, ProductionCostExpression, [service], model)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::IS.ModelConstructStage,
    model::ServiceModel{SR, StepwiseCostReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
) where {SR <: PSY.Reserve}
    name = get_service_name(model)
    service = PSY.get_component(SR, sys, name)
    contributing_devices = get_contributing_devices(model)

    add_constraints!(container, RequirementConstraint, service, contributing_devices, model)

    objective_function!(container, service, model)

    add_feedforward_constraints!(container, model, service)

    add_constraint_dual!(container, sys, model)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::IS.ArgumentConstructStage,
    model::ServiceModel{S, T},
    devices_template::Dict{Symbol, DeviceModel},
    ::Set{<:DataType},
) where {S <: PSY.AGC, T <: AbstractAGCFormulation}
    services = get_available_components(S, sys)
    agc_areas = PSY.get_area.(services)
    areas = PSY.get_components(PSY.Area, sys)
    if !isempty(setdiff(areas, agc_areas))
        throw(
            IS.ConflictingInputsError(
                "All area must have an AGC service assigned in order to model the System's Frequency regulation",
            ),
        )
    end

    add_variables!(container, SteadyStateFrequencyDeviation)
    add_variables!(container, AreaMismatchVariable, services, T())
    add_variables!(container, SmoothACE, services, T())
    add_variables!(container, LiftVariable, services, T())
    add_variables!(container, ActivePowerVariable, areas, T())
    add_variables!(container, DeltaActivePowerUpVariable, services, T())
    add_variables!(container, DeltaActivePowerDownVariable, services, T())
    add_variables!(container, AdditionalDeltaActivePowerUpVariable, areas, T())
    add_variables!(container, AdditionalDeltaActivePowerDownVariable, areas, T())

    add_initial_condition!(container, services, T(), AreaControlError())

    add_to_expression!(
        container,
        EmergencyUp,
        AdditionalDeltaActivePowerUpVariable,
        areas,
        model,
    )

    add_to_expression!(
        container,
        EmergencyDown,
        AdditionalDeltaActivePowerDownVariable,
        areas,
        model,
    )

    add_to_expression!(container, RawACE, SteadyStateFrequencyDeviation, services, model)

    add_feedforward_arguments!(container, model, services)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::IS.ModelConstructStage,
    model::ServiceModel{S, T},
    devices_template::Dict{Symbol, DeviceModel},
    ::Set{<:DataType},
) where {S <: PSY.AGC, T <: AbstractAGCFormulation}
    areas = PSY.get_components(PSY.Area, sys)
    services = get_available_components(S, sys)

    add_constraints!(container, AbsoluteValueConstraint, LiftVariable, services, model)
    add_constraints!(
        container,
        FrequencyResponseConstraint,
        SteadyStateFrequencyDeviation,
        services,
        model,
        sys,
    )
    add_constraints!(
        container,
        SACEPIDAreaConstraint,
        SteadyStateFrequencyDeviation,
        services,
        model,
        sys,
    )
    add_constraints!(container, BalanceAuxConstraint, SmoothACE, services, model, sys)

    add_feedforward_constraints!(container, model, services)

    add_constraint_dual!(container, sys, model)

    objective_function!(container, services, model)
    return
end

"""
    Constructs a service for StaticReserveGroup.
"""
function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::IS.ArgumentConstructStage,
    model::ServiceModel{SR, GroupReserve},
    ::Dict{Symbol, DeviceModel},
    ::Set{<:DataType},
) where {SR <: PSY.StaticReserveGroup}
    name = get_service_name(model)
    service = PSY.get_component(SR, sys, name)
    contributing_services = PSY.get_contributing_services(service)
    # check if variables exist
    check_activeservice_variables(container, contributing_services)

    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::IS.ModelConstructStage,
    model::ServiceModel{SR, GroupReserve},
    ::Dict{Symbol, DeviceModel},
    ::Set{<:DataType},
) where {SR <: PSY.StaticReserveGroup}
    name = get_service_name(model)
    service = PSY.get_component(SR, sys, name)
    contributing_services = PSY.get_contributing_services(service)

    add_constraints!(
        container,
        RequirementConstraint,
        service,
        contributing_services,
        model,
    )

    add_constraint_dual!(container, sys, model)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::IS.ArgumentConstructStage,
    model::ServiceModel{SR, RampReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
) where {SR <: PSY.Reserve}
    name = get_service_name(model)
    service = PSY.get_component(SR, sys, name)
    contributing_devices = get_contributing_devices(model)
    add_parameters!(container, RequirementTimeSeriesParameter, service, model)

    add_variables!(
        container,
        ActivePowerReserveVariable,
        service,
        contributing_devices,
        RampReserve(),
    )
    add_to_expression!(container, ActivePowerReserveVariable, model, devices_template)
    add_feedforward_arguments!(container, model, service)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::IS.ModelConstructStage,
    model::ServiceModel{SR, RampReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
) where {SR <: PSY.Reserve}
    name = get_service_name(model)
    service = PSY.get_component(SR, sys, name)
    contributing_devices = get_contributing_devices(model)

    add_constraints!(container, RequirementConstraint, service, contributing_devices, model)
    add_constraints!(container, RampConstraint, service, contributing_devices, model)
    add_constraints!(
        container,
        ParticipationFractionConstraint,
        service,
        contributing_devices,
        model,
    )

    objective_function!(container, service, model)

    add_feedforward_constraints!(container, model, service)

    add_constraint_dual!(container, sys, model)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::IS.ArgumentConstructStage,
    model::ServiceModel{SR, NonSpinningReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
) where {SR <: PSY.ReserveNonSpinning}
    name = get_service_name(model)
    service = PSY.get_component(SR, sys, name)
    contributing_devices = get_contributing_devices(model)
    add_parameters!(container, RequirementTimeSeriesParameter, service, model)

    add_variables!(
        container,
        ActivePowerReserveVariable,
        service,
        contributing_devices,
        NonSpinningReserve(),
    )
    add_feedforward_arguments!(container, model, service)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::IS.ModelConstructStage,
    model::ServiceModel{SR, NonSpinningReserve},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
) where {SR <: PSY.ReserveNonSpinning}
    name = get_service_name(model)
    service = PSY.get_component(SR, sys, name)
    contributing_devices = get_contributing_devices(model)

    add_constraints!(container, RequirementConstraint, service, contributing_devices, model)
    add_constraints!(
        container,
        ReservePowerConstraint,
        service,
        contributing_devices,
        model,
    )

    add_constraints!(
        container,
        ParticipationFractionConstraint,
        service,
        contributing_devices,
        model,
    )

    objective_function!(container, service, model)

    add_feedforward_constraints!(container, model, service)

    add_constraint_dual!(container, sys, model)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::IS.ArgumentConstructStage,
    model::ServiceModel{T, ConstantMaxInterfaceFlow},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
) where {T <: PSY.TransmissionInterface}
    interfaces = get_available_components(T, sys)
    if get_use_slacks(model)
        # Adding the slacks can be done in a cleaner fashion
        interface = PSY.get_component(T, sys, get_service_name(model))
        @assert PSY.get_available(interface)
        transmission_interface_slacks!(container, interface)
    end
    # Lazy container addition for the expressions.
    lazy_container_addition!(
        container,
        InterfaceTotalFlow(),
        T,
        PSY.get_name.(interfaces),
        get_time_steps(container),
    )
    #add_feedforward_arguments!(container, model, service)
    return
end

function construct_service!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::IS.ModelConstructStage,
    model::ServiceModel{T, ConstantMaxInterfaceFlow},
    devices_template::Dict{Symbol, DeviceModel},
    incompatible_device_types::Set{<:DataType},
) where {T <: PSY.TransmissionInterface}
    name = get_service_name(model)
    service = PSY.get_component(T, sys, name)

    add_to_expression!(
        container,
        InterfaceTotalFlow,
        FlowActivePowerVariable,
        service,
        model,
    )

    if get_use_slacks(model)
        add_to_expression!(
            container,
            InterfaceTotalFlow,
            InterfaceFlowSlackUp,
            service,
            model,
        )
        add_to_expression!(
            container,
            InterfaceTotalFlow,
            InterfaceFlowSlackDown,
            service,
            model,
        )
    end

    add_constraints!(container, InterfaceFlowLimit, service, model)
    add_feedforward_constraints!(container, model, service)
    add_constraint_dual!(container, sys, model)
    objective_function!(container, service, model)
    return
end
