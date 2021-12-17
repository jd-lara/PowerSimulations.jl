@testset "Single stage sequential tests" begin
    template_ed = get_template_nomin_ed_simulation()
    c_sys = PSB.build_system(PSITestSystems, "c_sys5_uc")
    models = SimulationModels([
        DecisionModel(template_ed, c_sys, name = "ED", optimizer = ipopt_optimizer),
    ])
    test_sequence =
        SimulationSequence(models = models, ini_cond_chronology = InterProblemChronology())
    sim_single = Simulation(
        name = "consecutive",
        steps = 2,
        models = models,
        sequence = test_sequence,
        simulation_folder = mktempdir(cleanup = true),
    )
    build_out = build!(sim_single)
    @test build_out == PSI.BuildStatus.BUILT
    execute_out = execute!(sim_single)
    @test execute_out == PSI.RunStatus.SUCCESSFUL
end

@testset "All stages executed - No Cache" begin
    template_uc = get_template_basic_uc_simulation()
    template_ed = get_template_nomin_ed_simulation()
    set_device_model!(template_ed, InterruptibleLoad, StaticPowerLoad)
    set_device_model!(template_ed, HydroEnergyReservoir, HydroDispatchReservoirBudget)
    set_network_model!(template_uc, NetworkModel(
        CopperPlatePowerModel,
        # TODO: Duals currently not working 
        # duals = [CopperPlateBalanceConstraint],
        use_slacks = true,
    ))
    set_network_model!(template_ed, NetworkModel(
        CopperPlatePowerModel,
        # TODO: Duals currently not working 
        # duals = [CopperPlateBalanceConstraint],
        use_slacks = true,
    ))
    c_sys5_hy_uc = PSB.build_system(PSITestSystems, "c_sys5_hy_uc")
    c_sys5_hy_ed = PSB.build_system(PSITestSystems, "c_sys5_hy_ed")
    models = SimulationModels(
        decision_models = [
            DecisionModel(
                template_uc,
                c_sys5_hy_uc;
                name = "UC",
                optimizer = GLPK_optimizer,
            ),
            DecisionModel(
                template_ed,
                c_sys5_hy_ed;
                name = "ED",
                optimizer = ipopt_optimizer,
            ),
        ],
    )

    sequence = SimulationSequence(
        models = models,
        feedforwards = Dict(
            "ED" => [
                SemiContinuousFeedforward(
                    component_type = ThermalStandard,
                    source = OnVariable,
                    affected_values = [ActivePowerVariable],
                ),
                IntegralLimitFeedforward(
                    component_type = HydroEnergyReservoir,
                    source = ActivePowerVariable,
                    affected_values = [ActivePowerVariable],
                    number_of_periods = 12,
                ),
            ],
        ),
        ini_cond_chronology = InterProblemChronology(),
    )
    sim = Simulation(
        name = "no_cache",
        steps = 2,
        models = models,
        sequence = sequence,
        simulation_folder = mktempdir(cleanup = true),
    )

    build_out = build!(sim; console_level = Logging.Error)
    @test build_out == PSI.BuildStatus.BUILT
    execute_out = execute!(sim)
    @test execute_out == PSI.RunStatus.SUCCESSFUL
end

@testset "Simulation Single Stage with Cache" begin
    c_sys5_hy_ed = PSB.build_system(PSITestSystems, "c_sys5_hy_ems_ed")
    template = get_template_hydro_st_ed()
    models = SimulationModels(
        decision_models = [
            DecisionModel(template, c_sys5_hy_ed; name = "ED", optimizer = ipopt_optimizer),
        ],
    )

    single_sequence =
        SimulationSequence(models = models, ini_cond_chronology = IntraProblemChronology())

    sim_single_wcache = Simulation(
        name = "cache_st",
        steps = 2,
        models = models,
        sequence = single_sequence,
        simulation_folder = mktempdir(cleanup = true),
    )
    build_out = build!(sim_single_wcache)
    @test build_out == PSI.BuildStatus.BUILT
    # TODO: IntraProblemChronology not implemented
    # execute_out = execute!(sim_single_wcache)
    # @test execute_out == PSI.RunStatus.SUCCESSFUL
end

@testset "Simulation with 2-Stages and Cache" begin
    template_uc =
        get_template_hydro_st_uc(NetworkModel(CopperPlatePowerModel, use_slacks = true))
    template_ed =
        get_template_hydro_st_ed(NetworkModel(CopperPlatePowerModel, use_slacks = true))
    set_device_model!(template_ed, InterruptibleLoad, StaticPowerLoad)
    c_sys5_hy_uc = PSB.build_system(PSITestSystems, "c_sys5_hy_ems_uc")
    c_sys5_hy_ed = PSB.build_system(PSITestSystems, "c_sys5_hy_ems_ed")
    models = SimulationModels(
        decision_models = [
            DecisionModel(
                template_uc,
                c_sys5_hy_uc;
                name = "UC",
                optimizer = GLPK_optimizer,
            ),
            DecisionModel(
                template_ed,
                c_sys5_hy_ed;
                name = "ED",
                optimizer = GLPK_optimizer,
            ),
        ],
    )

    sequence_cache = SimulationSequence(
        models = models,
        feedforwards = Dict(
            "ED" => [
                SemiContinuousFeedforward(
                    component_type = ThermalStandard,
                    source = OnVariable,
                    affected_values = [ActivePowerVariable],
                ),
                IntegralLimitFeedforward(
                    component_type = HydroEnergyReservoir,
                    source = ActivePowerVariable,
                    affected_values = [ActivePowerVariable],
                    number_of_periods = 12,
                ),
            ],
        ),
        ini_cond_chronology = InterProblemChronology(),
    )
    sim_cache = Simulation(
        name = "cache",
        steps = 2,
        models = models,
        sequence = sequence_cache,
        simulation_folder = mktempdir(cleanup = true),
    )
    build_out = build!(sim_cache)
    @test build_out == PSI.BuildStatus.BUILT
    execute_out = execute!(sim_cache)
    @test execute_out == PSI.RunStatus.SUCCESSFUL
end

@testset "Test Recedin Horizon Chronology" begin
    template_uc = get_template_basic_uc_simulation()
    # network slacks added because of data issues
    template_ed = get_template_nomin_ed_simulation(
        NetworkModel(CopperPlatePowerModel, use_slacks = true),
    )
    c_sys5_hy_uc = PSB.build_system(PSITestSystems, "c_sys5_hy_uc")
    c_sys5_hy_ed = PSB.build_system(PSITestSystems, "c_sys5_hy_ed")
    models = SimulationModels(
        decision_models = [
            DecisionModel(
                template_uc,
                c_sys5_hy_uc;
                name = "UC",
                optimizer = GLPK_optimizer,
            ),
            DecisionModel(
                template_ed,
                c_sys5_hy_ed;
                name = "ED",
                optimizer = ipopt_optimizer,
            ),
        ],
    )

    sequence = SimulationSequence(
        models = models,
        feedforwards = Dict(
            "ED" => [
                SemiContinuousFeedforward(
                    component_type = ThermalStandard,
                    source = OnVariable,
                    affected_values = [ActivePowerVariable],
                ),
            ],
        ),
        ini_cond_chronology = InterProblemChronology(),
    )

    sim = Simulation(
        name = "receding_horizon",
        steps = 1,
        models = models,
        sequence = sequence,
        simulation_folder = mktempdir(cleanup = true),
    )
    build_out = build!(sim)
    @test build_out == PSI.BuildStatus.BUILT
    execute_out = execute!(sim)
    @test execute_out == PSI.RunStatus.SUCCESSFUL
end

@testset "Test SemiContinuous Feedforward with Active and Reactive Power variables" begin
    template_uc = get_template_basic_uc_simulation()
    set_network_model!(template_uc, NetworkModel(ACPPowerModel, use_slacks = true))
    # network slacks added because of data issues
    template_ed =
        get_template_nomin_ed_simulation(NetworkModel(ACPPowerModel, use_slacks = true))
    c_sys5_hy_uc = PSB.build_system(PSITestSystems, "c_sys5_hy_uc")
    c_sys5_hy_ed = PSB.build_system(PSITestSystems, "c_sys5_hy_ed")
    models = SimulationModels(
        decision_models = [
            DecisionModel(
                template_uc,
                c_sys5_hy_uc;
                name = "UC",
                optimizer = Cbc_optimizer,
                initialize_model = false,
            ),
            DecisionModel(
                template_ed,
                c_sys5_hy_ed;
                name = "ED",
                optimizer = Cbc_optimizer,
                initialize_model = false,
            ),
        ],
    )

    sequence = SimulationSequence(
        models = models,
        feedforwards = Dict(
            "ED" => [
                SemiContinuousFeedforward(
                    component_type = ThermalStandard,
                    source = OnVariable,
                    affected_values = [ActivePowerVariable, ReactivePowerVariable],
                ),
            ],
        ),
        ini_cond_chronology = InterProblemChronology(),
    )

    sim = Simulation(
        name = "reactive_feedforward",
        steps = 2,
        models = models,
        sequence = sequence,
        simulation_folder = mktempdir(cleanup = true),
    )
    build_out = build!(sim)
    @test build_out == PSI.BuildStatus.BUILT
    # execute_out = execute!(sim)
    # @test execute_out == PSI.RunStatus.SUCCESSFUL
end

@testset "Test Simulation Utils" begin
    template_uc = get_template_basic_uc_simulation()
    set_network_model!(template_uc, NetworkModel(
        CopperPlatePowerModel,
        use_slacks = true,
        # TODO: Duals currently not working 
        # duals = [CopperPlateBalanceConstraint],
    ))

    template_ed = get_template_nomin_ed_simulation(
        NetworkModel(
            CopperPlatePowerModel;
            # Added because of data issues
            use_slacks = true,
            # TODO: Duals currently not working 
            # duals = [CopperPlateBalanceConstraint],
        ),
    )
    set_device_model!(template_ed, InterruptibleLoad, StaticPowerLoad)
    set_device_model!(template_ed, HydroEnergyReservoir, HydroDispatchReservoirBudget)
    c_sys5_hy_uc = PSB.build_system(PSITestSystems, "c_sys5_hy_uc")
    c_sys5_hy_ed = PSB.build_system(PSITestSystems, "c_sys5_hy_ed")
    models = SimulationModels(
        decision_models = [
            DecisionModel(
                template_uc,
                c_sys5_hy_uc;
                name = "UC",
                optimizer = GLPK_optimizer,
            ),
            DecisionModel(
                template_ed,
                c_sys5_hy_ed;
                name = "ED",
                optimizer = ipopt_optimizer,
            ),
        ],
    )

    sequence = SimulationSequence(
        models = models,
        feedforwards = Dict(
            "ED" => [
                SemiContinuousFeedforward(
                    component_type = ThermalStandard,
                    source = OnVariable,
                    affected_values = [ActivePowerVariable],
                ),
                IntegralLimitFeedforward(
                    component_type = HydroEnergyReservoir,
                    source = ActivePowerVariable,
                    affected_values = [ActivePowerVariable],
                    number_of_periods = 12,
                ),
            ],
        ),
        ini_cond_chronology = InterProblemChronology(),
    )
    sim = Simulation(
        name = "aggregation",
        steps = 2,
        models = models,
        sequence = sequence,
        simulation_folder = mktempdir(cleanup = false),
    )

    build_out = build!(sim; console_level = Logging.Info)
    @test build_out == PSI.BuildStatus.BUILT
    execute_out = execute!(sim)
    @test execute_out == PSI.RunStatus.SUCCESSFUL

    #= 
    TODO: The recorder test are not passing  
    @testset "Verify simulation events" begin
        file = joinpath(PSI.get_simulation_dir(sim), "recorder", "simulation_status.log")
        @test isfile(file)
        events = PSI.list_simulation_events(
            PSI.InitialConditionUpdateEvent,
            PSI.get_simulation_dir(sim);
            step = 1,
        )
        @test length(events) == 0
        events = PSI.list_simulation_events(
            PSI.InitialConditionUpdateEvent,
            PSI.get_simulation_dir(sim);
            step = 2,
        )
        @test length(events) == 10
        PSI.show_simulation_events(
            devnull,
            PSI.InitialConditionUpdateEvent,
            PSI.get_simulation_dir(sim),
            ;
            step = 2,
        )
        events = PSI.list_simulation_events(
            PSI.InitialConditionUpdateEvent,
            PSI.get_simulation_dir(sim);
            step = 1,
            problem = 1,
        )
        @test length(events) == 0
        events = PSI.list_simulation_events(
            PSI.InitialConditionUpdateEvent,
            PSI.get_simulation_dir(sim),
            ;
            step = 2,
            problem = 1,
        )
        @test length(events) == 10
        PSI.show_simulation_events(
            devnull,
            PSI.InitialConditionUpdateEvent,
            PSI.get_simulation_dir(sim),
            ;
            step = 2,
            problem = 1,
        )
    end

    @testset "Check Serialization - Deserialization of Sim" begin
        path = mktempdir()
        files_path = PSI.serialize_simulation(sim; path = path)
        deserialized_sim = Simulation(files_path, stage_info)
        build_out = build!(deserialized_sim)
        @test build_out == PSI.BuildStatus.BUILT
        for stage in values(PSI.get_stages(deserialized_sim))
            @test PSI.is_stage_built(stage)
        end
    end
    =#
    # TODO: Enable for test coverage later
    # @testset "Test print methods" begin
    #     list = [sim, sim.sequence, sim.stages["UC"]]
    #     _test_plain_print_methods(list)
    # end
end
