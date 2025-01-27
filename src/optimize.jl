include("clusters.jl")
include("planetary_catalog.jl")
include("optimization.jl")

sim_param = setup_sim_param_model()





##### To start saving the model iterations in the optimization into a file:

model_name = "Clustered_P_R_broken_R_optimization"
optimization_number = "_random"*ARGS[1] # if want to run on the cluster with random initial active parameters: "_random"*ARGS[1]
use_KS_or_AD = "KS" # 'KS' or 'AD' or 'Both' (need to be careful counting indices for 'dists_exclude'!!!)
AD_mod = true
Kep_or_Sim = "Kep" # 'Kep' or 'Sim'
num_targs = 79935
max_incl_sys = 0.
max_evals = 5000
dists_exclude = [2,3,8,12,13,15,16,17] # Int64[] if want to include all distances
Pop_per_param = 4

file_name = model_name*optimization_number*"_targs$(num_targs)_evals$(max_evals).txt"
f = open(file_name, "w")
println(f, "# All initial parameters:")
write_model_params(f, sim_param)





##### To run the same model multiple times to see how it compares to a simulated catalog with the same parameters:

using Random
Random.seed!(1234) # to have the same reference catalog and simulated catalogs for calculating the weights

# To generate a simulated catalog to fit to:
cat_phys = generate_kepler_physical_catalog(sim_param)
cat_phys_cut = ExoplanetsSysSim.generate_obs_targets(cat_phys,sim_param)
cat_obs = observe_kepler_targets_single_obs(cat_phys_cut,sim_param)
summary_stat_ref = calc_summary_stats_model(cat_obs,sim_param)

# To simulate more observed planets for the subsequent model generations:
add_param_fixed(sim_param,"num_targets_sim_pass_one", num_targs)
add_param_fixed(sim_param,"max_incl_sys", max_incl_sys) # degrees; 0 (deg) for isotropic system inclinations; set closer to 90 (deg) for more transiting systems

active_param_true, weights, target_fitness, target_fitness_std = compute_weights_target_fitness_std_from_file("Clustered_P_R_broken_R_weights_ADmod_$(AD_mod)_targs399675_evals1000.txt", 1000, use_KS_or_AD ; weight=true, dists_exclude=dists_exclude, save_dist=true)





##### To draw the initial values of the active parameters randomly within a search range:

transformed_indices = [9,10]
active_param_keys = ["f_high_incl", "f_stars_with_planets_attempted", "log_rate_clusters", "log_rate_planets_per_cluster", "power_law_P", "power_law_r1", "power_law_r2", "sigma_hk", "sigma_incl", "sigma_incl_near_mmr", "sigma_log_radius_in_cluster", "sigma_logperiod_per_pl_in_cluster"]
active_params_box = [(0., 1.), (0., 1.), (log(0.5), log(5.)), (log(0.5), log(5.)), (-2., 2.), (-4., 2.), (-6., 0.), (0., 0.1), (0., 1.), (0., 1.), (0., 0.5), (0., 0.3)] #search ranges for all of the active parameters
transformed_triangle = [[0., 0.], [30., 30.], [30., 0.]] # vertices (x,y) of the triangle for the transformed params

# To randomly draw (uniformly) a value for each active model parameter within its search range:

Random.seed!() # to have a random set of initial parameters and optimization run

for (i,param_key) in enumerate(active_param_keys)
    if ~in(i,transformed_indices)
        active_param_draw = active_params_box[i][1] .+ (active_params_box[i][2] - active_params_box[i][1])*rand(1)
        add_param_active(sim_param,param_key,active_param_draw[1])
    end
end
r1_r2 = rand(2)
transformed_params = map_square_to_triangle(r1_r2[1], r1_r2[2], transformed_triangle[1], transformed_triangle[2], transformed_triangle[3])
add_param_active(sim_param, active_param_keys[transformed_indices[1]], transformed_params[1])
add_param_active(sim_param, active_param_keys[transformed_indices[2]], transformed_params[2])
active_param_start = make_vector_of_sim_param(sim_param)
active_param_transformed_start = deepcopy(active_param_start)
active_param_transformed_start[transformed_indices] = r1_r2

PopSize = length(active_param_true)*Pop_per_param

println("# Active parameters: ", make_vector_of_active_param_keys(sim_param))
println(f, "# Active parameters: ", make_vector_of_active_param_keys(sim_param))
println(f, "# Starting active parameter values: ", active_param_start)
println(f, "# Optimization active parameters search bounds: ", active_params_box)
println(f, "# Transformed active parameters: ", make_vector_of_active_param_keys(sim_param)[transformed_indices])
if length(transformed_indices) > 0
    println(f, "# Transformed active parameters search triangle vertices: ", transformed_triangle)
end
println(f, "# Method: adaptive_de_rand_1_bin_radiuslimited")
println(f, "# PopulationSize: ", PopSize)
println(f, "# Format: Active_params: [active parameter values]")
println(f, "# Format: Dist: [distances][total distance]")
println(f, "# Format: Dist_weighted: [weighted distances][total weighted distance]")
println(f, "# Distances used: ", use_KS_or_AD)
println(f, "# AD_mod: ", AD_mod)
println(f, "#")

#target_function(active_param_start, use_KS_or_AD, Kep_or_Sim ; AD_mod=AD_mod, weights=weights, all_dist=false, save_dist=true) #to simulate the model once with the drawn parameters before starting the optimization
target_function_transformed_params(active_param_transformed_start, transformed_indices, transformed_triangle[1], transformed_triangle[2], transformed_triangle[3], use_KS_or_AD, Kep_or_Sim ; AD_mod=AD_mod, weights=weights, all_dist=false, save_dist=true) # to simulate the model once with the drawn parameters before starting the optimization





##### To use automated optimization routines to optimize the active model parameters:

# Pkg.add("BlackBoxOptim")       # only need to do these once
# Pkg.checkout("BlackBoxOptim")  # needed to get the lastest version
using BlackBoxOptim              # see https://github.com/robertfeldt/BlackBoxOptim.jl for documentation

t_elapsed = @elapsed begin
    #opt_result = bboptimize(active_params -> target_function(active_params, use_KS_or_AD, Kep_or_Sim ; AD_mod=AD_mod, weights=weights, all_dist=false, save_dist=true); SearchRange = active_params_box, NumDimensions = length(active_param_true), Method = :adaptive_de_rand_1_bin_radiuslimited, PopulationSize = PopSize, MaxFuncEvals = max_evals, TargetFitness = target_fitness, FitnessTolerance = target_fitness_std, TraceMode = :verbose)

    opt_result = bboptimize(active_params -> target_function_transformed_params(active_params, transformed_indices, transformed_triangle[1], transformed_triangle[2], transformed_triangle[3], use_KS_or_AD, Kep_or_Sim ; AD_mod=AD_mod, weights=weights, all_dist=false, save_dist=true); SearchRange = active_params_box, NumDimensions = length(active_param_true), Method = :adaptive_de_rand_1_bin_radiuslimited, PopulationSize = PopSize, MaxFuncEvals = max_evals, TargetFitness = target_fitness, FitnessTolerance = target_fitness_std, TraceMode = :verbose)
end

println(f, "# best_candidate: ", best_candidate(opt_result))
println(f, "# best_fitness: ", best_fitness(opt_result))
println(f, "# elapsed time: ", t_elapsed, " seconds")
close(f)
