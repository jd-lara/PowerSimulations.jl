function _pass_abstract_jump(optimizer::Union{Nothing, JuMP.OptimizerFactory},
                              parameters::Bool,
                              JuMPmodel::Union{JuMP.AbstractModel,Nothing})
    if isa(optimizer, Nothing)
        @info("The optimization model has no optimizer attached")
    end
    if !isnothing(JuMPmodel)
        if parameters
            if !haskey(JuMPmodel.ext, :params)
                @info("Model doesn't have Parameters enabled. Parameters will be enabled")
            end
            PJ.enable_parameters(JuMPmodel)
        end
        return JuMPmodel
    end
    JuMPmodel = JuMP.Model(optimizer)
    if parameters
        PJ.enable_parameters(JuMPmodel)
    end
    return JuMPmodel
end

function _make_container_array(V::DataType, parameters::Bool, ax...)

    if parameters
        return JuMP.Containers.DenseAxisArray{PGAE{V}}(undef, ax...)
    else
        return JuMP.Containers.DenseAxisArray{GAE{V}}(undef, ax...)
    end

    return

end

function _make_expressions_dict(transmission::Type{S},
                                V::DataType,
                                bus_numbers::Vector{Int64},
                                time_steps::UnitRange{Int64},
                                parameters::Bool) where {S<:PM.AbstractPowerModel}

    return DSDA(:nodal_balance_active =>  _make_container_array(V,
                                                                parameters,
                                                                bus_numbers,
                                                                time_steps),
                :nodal_balance_reactive => _make_container_array(V,
                                                                 parameters,
                                                                 bus_numbers,
                                                                 time_steps))

end

function _make_expressions_dict(transmission::Type{S},
                                V::DataType,
                                bus_numbers::Vector{Int64},
                                time_steps::UnitRange{Int64},
                                parameters::Bool) where {S<:PM.AbstractActivePowerModel}

    return DSDA(:nodal_balance_active =>  _make_container_array(V,
                                                                parameters,
                                                                bus_numbers,
                                                                time_steps))
end


function _canonical_init(bus_numbers::Vector{Int64},
                        jump_model::JuMP.AbstractModel,
                        optimizer::Union{Nothing,JuMP.OptimizerFactory},
                        transmission::Type{S},
                        time_steps::UnitRange{Int64},
                        resolution::Dates.Period,
                        use_forecast_data::Bool,
                        initial_time::Dates.DateTime,
                        make_parameters_container::Bool,
                        ini_con::DICKDA) where {S<:PM.AbstractPowerModel}

    V = JuMP.variable_type(jump_model)

    canonical = CanonicalModel(jump_model,
                              optimizer,
                              time_steps,
                              resolution,
                              use_forecast_data,
                              initial_time,
                              DSDA(),
                              DSDA(),
                              zero(JuMP.GenericAffExpr{Float64, V}),
                              _make_expressions_dict(transmission,
                                                     V,
                                                     bus_numbers,
                                                     time_steps,
                                                     make_parameters_container),
                              make_parameters_container ? DRDA() : nothing,
                              ini_con,
                              nothing);

    return canonical

end

mutable struct CanonicalModel
    JuMPmodel::JuMP.AbstractModel
    optimizer_factory::Union{Nothing, JuMP.OptimizerFactory}
    time_steps::UnitRange{Int64}
    resolution::Dates.Period
    use_forecast_data::Bool
    initial_time::Dates.DateTime
    variables::Dict{Symbol, JuMP.Containers.DenseAxisArray}
    constraints::Dict{Symbol, JuMP.Containers.DenseAxisArray}
    cost_function::JuMP.AbstractJuMPScalar
    expressions::Dict{Symbol, JuMP.Containers.DenseAxisArray}
    parameters::Union{Nothing, Dict{UpdateRef, JuMP.Containers.DenseAxisArray}}
    initial_conditions::DICKDA
    pm_model::Union{Nothing, PM.AbstractPowerModel}

    function CanonicalModel(JuMPmodel::JuMP.AbstractModel,
                            optimizer_factory::Union{Nothing, JuMP.OptimizerFactory},
                            time_steps::UnitRange{Int64},
                            resolution::Dates.Period,
                            use_forecast_data::Bool,
                            initial_time::Dates.DateTime,
                            variables::Dict{Symbol, JuMP.Containers.DenseAxisArray},
                            constraints::Dict{Symbol, JuMP.Containers.DenseAxisArray},
                            cost_function::JuMP.AbstractJuMPScalar,
                            expressions::Dict{Symbol, JuMP.Containers.DenseAxisArray},
                            parameters::Union{Nothing, Dict{UpdateRef, JuMP.Containers.DenseAxisArray}},
                            initial_conditions::DICKDA,
                            pm_model::Union{Nothing, PM.AbstractPowerModel})

        new(JuMPmodel,
            optimizer_factory,
            time_steps,
            resolution,
            use_forecast_data,
            initial_time,
            variables,
            constraints,
            cost_function,
            expressions,
            parameters,
            initial_conditions,
            pm_model)

    end

end

function CanonicalModel(::Type{T},
                        sys::PSY.System,
                        optimizer::Union{Nothing,JuMP.OptimizerFactory};
                        kwargs...) where {T<:PM.AbstractPowerModel}

    PSY.check_forecast_consistency(sys)
    user_defined_model = get(kwargs, :JuMPmodel, nothing)
    ini_con = get(kwargs, :initial_conditions, DICKDA())
    make_parameters_container = get(kwargs, :use_parameters, false)
    use_forecast_data = get(kwargs, :use_forecast_data, true)
    jump_model = _pass_abstract_jump(optimizer, make_parameters_container, user_defined_model)
    initial_time = get(kwargs, :initial_time, PSY.get_forecasts_initial_time(sys))

    if use_forecast_data
        horizon = get(kwargs, :horizon, PSY.get_forecasts_horizon(sys))
        time_steps = 1:horizon
        resolution = PSY.get_forecasts_resolution(sys)
    else
        resolution = PSY.get_forecasts_resolution(sys)
        time_steps = 1:1
    end

    bus_numbers = sort([PSY.get_number(b) for b in PSY.get_components(PSY.Bus, sys)])

    return _canonical_init(bus_numbers,
                           jump_model,
                           optimizer,
                           T,
                           time_steps,
                           resolution,
                           use_forecast_data,
                           initial_time,
                           make_parameters_container,
                           ini_con)

end

function InitialCondition(canonical::CanonicalModel,
                          device::T,
                          access_ref::Symbol,
                          value::Float64,
                          cache::Union{Nothing, Type{<:AbstractCache}}=nothing) where T <: PSY.Device

    if model_has_parameters(canonical)
        return InitialCondition(device,
                                UpdateRef{JuMP.VariableRef}(access_ref),
                                PJ.add_parameter(canonical.JuMPmodel, value),
                                cache)
    else
        !hasfield(T, access_ref) && error("Device of of type $(T) doesn't contain
                                            the field $(access_ref)")
        return InitialCondition(device,
                                UpdateRef{T}(access_ref),
                                value,
                                cache)
    end

end

function get_initial_conditions(canonical::CanonicalModel, key::ICKey)
    return get(canonical.initial_conditions, key, Vector{InitialCondition}())
end

# Var_ref
function get_value(canonical::CanonicalModel, ref::UpdateRef{JuMP.VariableRef})
    return var(canonical, ref.access_ref)
end

# param_ref
function get_value(canonical::CanonicalModel, ref::UpdateRef{PJ.ParameterRef})
    for (k, v) in canonical.parameters
        if k.access_ref == ref.access_ref
            return v
        end
    end
    return
end

_variable_type(cm::CanonicalModel) = JuMP.variable_type(cm.JuMPmodel)
model_time_steps(canonical::CanonicalModel) = canonical.time_steps
model_resolution(canonical::CanonicalModel) = canonical.resolution
model_has_parameters(canonical::CanonicalModel) = !isnothing(canonical.parameters)
model_uses_forecasts(canonical::CanonicalModel) = canonical.use_forecast_data
model_initial_time(canonical::CanonicalModel) = canonical.initial_time
#Internal Variables, Constraints and Parameters accessors
vars(canonical::CanonicalModel) = canonical.variables
cons(canonical::CanonicalModel) = canonical.constraints
var(canonical::CanonicalModel, name::Symbol) = canonical.variables[name]
con(canonical::CanonicalModel, name::Symbol) = canonical.constraints[name]
par(canonical::CanonicalModel, param_reference::UpdateRef) = canonical.parameters[param_reference]
exp(canonical::CanonicalModel, name::Symbol) = canonical.expressions[name]
get_initial_conditions(canonical::CanonicalModel) = canonical.initial_conditions