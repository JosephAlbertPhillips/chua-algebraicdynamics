using AlgebraicDynamics
using Catlab.WiringDiagrams, Catlab.Programs
using LinearAlgebra

using ComponentArrays
using OrdinaryDiffEq, Plots, Plots.PlotMeasures
using Random
Random.seed!(1)

#Kennedy's Nonlinear Resistor
g(x,p) = p.m0*x+0.5*(p.m1-p.m0)*(abs(x+p.Bp)-abs(x-p.Bp))

# Define the primitive systems
dotvc1(u, x, p, t)  = [(1/p.C1)*((1/p.R)*(x[1]-u[1])-g(u[1],p))]
dotvc2(u, x, p, t)  = [(1/p.C2)*((1/p.R)*(x[1]-u[1])+x[2])]
dotil(u, x, p, t)   = [-(1/p.L)*x[1]]

volt_cap_1  = ContinuousMachine{Float64}(1, 1, 1, dotvc1, (u, p, t) -> u)
volt_cap_2  = ContinuousMachine{Float64}(2, 1, 1, dotvc2, (u, p, t) -> u)
current     = ContinuousMachine{Float64}(1, 1, 1, dotil, (u, p, t) -> u)

# Define the composition pattern
chua_circuit_pattern    = WiringDiagram([], [:volt_cap_1, :volt_cap_2, :inductor_current]) 
volt_cap_1_box          = add_box!(chua_circuit_pattern, Box(:volt_cap_1, [:v], [:v]))
volt_cap_2_box          = add_box!(chua_circuit_pattern, Box(:volt_cap_2, [:v, :i], [:v]))
current_box             = add_box!(chua_circuit_pattern, Box(:inductor_current, [:v], [:i]))

add_wires!(chua_circuit_pattern, Pair[
    (volt_cap_1_box, 1) => (volt_cap_2_box, 1)
    (volt_cap_2_box, 1) => (volt_cap_1_box, 1)
    (volt_cap_2_box, 1) => (current_box, 1)
    (current_box, 1) => (volt_cap_2_box, 2)
    (volt_cap_1_box, 1) => (output_id(chua_circuit_pattern), 1)
    (volt_cap_2_box, 1) => (output_id(chua_circuit_pattern), 2)
    (current_box, 1) => (output_id(chua_circuit_pattern), 3)
])

# Compose 
chua_circuit_system = oapply(chua_circuit_pattern, [volt_cap_1, volt_cap_2, current])

# Solve
u0  = [0.1, 0.0, 0.0]
params  = ComponentArray(C1=10e-9, C2=100e-9, R=1/565e-6 , L = 18e-3, 
                            m0= -409.09e-6, m1= -757.576e-6, Bp= 1.0)
tspan   = (0.0, 0.05)

prob_directed   = ODEProblem(chua_circuit_system, u0, tspan, params)
sol             = solve(prob_directed, Tsit5(); reltol=1e-10, abstol=1e-14)

# Verify Against The Dynamical System Equations

chua_ode(u, p, t)   = [(1/p.C1)*((1/p.R)*(u[2]-u[1])-g(u[1],p)), 
                        (1/p.C2)*((1/p.R)*(u[1]-u[2])+u[3]), 
                        -(1/p.L)*u[2]]

tspan_check         = (0.0, 1.0e-3)
initial_conditions  = [[2rand() - 1, 2rand() - 1, 2rand() - 1] for _ in 1:100]

relative_error(a, b)    = norm(a - b) / norm(b)
final_state_errors      = Float64[]

for u0 in initial_conditions
    composed_prob   = ODEProblem(chua_circuit_system, u0, tspan_check, params)
    composed_sol    = solve(composed_prob, Tsit5(); reltol=1e-10, abstol=1e-12)
    ode_prob        = ODEProblem(chua_ode, u0, tspan_check, params)
    ode_sol         = solve(ode_prob, Tsit5(); reltol=1e-10, abstol=1e-12)
    push!(final_state_errors, relative_error(composed_sol.u[end], ode_sol.u[end]))
end
println("Max relative distance of the composed method versus the reference ODE: ", maximum(final_state_errors))



# Used Claude to assist with plotting

ts = range(0.01, 0.05, length=40_000)
U  = reduce(hcat, sol.(ts))
v1, v2, iL = U[1,:], U[2,:], 1e3 .* U[3,:]

scroll = cgrad([:steelblue, :gray75, :darkorange])
style  = (line_z=v1, color=scroll, clims=(-4, 4), lw=0.4, colorbar=false,
          legend=false, grid=false, framestyle=:box)

p3 = plot3d(v1, v2, iL; style..., camera=(40, 25),
            xlabel="v₁ (V)", ylabel="v₂ (V)", zlabel="i_L (mA)")
pa = plot(v1, iL; style..., ylabel="i_L (mA)")
pb = plot(v1, v2; style..., xlabel="v₁ (V)", ylabel="v₂ (V)")

l = @layout [a{0.55w} grid(2, 1)]          # 3D takes 55% of the width; right side split in two
fig = plot(p3, pa, pb; layout=l, size=(1200, 600), margin=5Plots.mm,
           plot_title="Chua's circuit: double scroll", dpi=300)
#savefig(fig, "directed_double_scroll.png")

