function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ArgumentConstructStage,
    model::DeviceModel{PSY.InterconnectingConverter, LossLessConverter},
    ::Type{S},
) where {S <: PM.AbstractActivePowerModel}
    devices = get_available_components(PSY.InterconnectingConverter, sys)
    add_variables!(container, ActivePowerVariable, devices, LossLessConverter())
    add_to_expression!(
        container,
        ActivePowerBalanceAC,
        ActivePowerVariable,
        devices,
        model,
        S,
    )
    add_to_expression!(
        container,
        ActivePowerBalanceDC,
        ActivePowerVariable,
        devices,
        model,
        S,
    )

    add_feedforward_arguments!(container, model, devices)
    return
end

function construct_device!(
    container::OptimizationContainer,
    sys::PSY.System,
    ::ModelConstructStage,
    model::DeviceModel{PSY.InterconnectingConverter, LossLessConverter},
    ::Type{S},
) where {S <: PM.AbstractActivePowerModel}

    devices = get_available_components(T, sys)
    return
end
