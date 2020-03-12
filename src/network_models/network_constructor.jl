function construct_network!(
    psi_container::PSIContainer,
    sys::PSY.System,
    system_formulation::Type{CopperPlatePowerModel};
    parameters::Union{Nothing, NetworkOperationsParameters} = nothing,
)
    buses = PSY.get_components(PSY.Bus, sys)
    bus_count = length(buses)

    copper_plate(psi_container, :nodal_balance_active, bus_count)

    return
end

function construct_network!(
    psi_container::PSIContainer,
    sys::PSY.System,
    system_formulation::Type{StandardPTDFModel};
    parameters::NetworkOperationsParameters,
)
    buses = PSY.get_components(PSY.Bus, sys)
    ac_branches = PSY.get_components(PSY.ACBranch, sys)
    ptdf_networkflow(
        psi_container,
        ac_branches,
        buses,
        :nodal_balance_active,
        get_ptdf(parameters),
    )

    dc_branches = PSY.get_components(PSY.DCBranch, sys)
    dc_branch_types = typeof.(dc_branches)
    for btype in Set(dc_branch_types)
        typed_dc_branches = IS.FlattenIteratorWrapper(
            btype,
            Vector([[b for b in dc_branches if typeof(b) == btype]]),
        )
        flow_variables!(psi_container, StandardPTDFModel, typed_dc_branches)
    end

    return

end

function construct_network!(
    psi_container::PSIContainer,
    sys::PSY.System,
    ::Type{T};
    parameters::Union{Nothing, NetworkOperationsParameters} = nothing,
) where {T <: PM.AbstractPowerModel}
    incompat_list = [
        PM.SDPWRMPowerModel,
        PM.SparseSDPWRMPowerModel,
        PM.SOCBFPowerModel,
        PM.SOCBFConicPowerModel,
    ]

    if T in incompat_list
        throw(ArgumentError("$(T) formulation is not currently supported in PowerSimulations"))
    end
    powermodels_network!(psi_container, T, sys)
    add_pm_var_refs!(psi_container, T, sys)
    return
end
