using WORLD
using Base.Test
using WAV

# Check consistency of the results between WORLD and WORLD.jl.
# Due to the results of the WORLD were dumped (see ./data) on linux,
# we test consistency only on linux.
@linux_only include("consistency.jl")

function test_dio(x, fs::Int=44100, period::Float64=5.0)
    println("test_dio: fs=$(fs), period=$(period)")
    w = World(fs, period)
    opt = DioOption(80.0, 640.0, 2, period, 4)
    f0, timeaxis = dio(w, x; opt=opt)
    @test !any(isnan(f0))
    @test all(f0 .>= 0.0)
    @test !any(isnan(timeaxis))
end

function test_stonemask(x, fs::Int=44100, period::Float64=5.0)
    println("test_stonemask: fs=$(fs), period=$(period)")
    w = World(fs, period)
    opt = DioOption(80.0, 640.0, 2, period, 4)
    f0, timeaxis = dio(w, x; opt=opt)
    f0 = stonemask(w, x, timeaxis, f0)
    @test !any(isnan(f0))
    @test all(f0 .>= 0.0)
end

function test_envelope(x, fs::Int=44100, period::Float64=5.0,
                       usecheaptrick::Bool=true)
    w = World(fs, period)
    opt = DioOption(80.0, 640.0, 2, period, 4)
    f0, timeaxis = dio(w, x; opt=opt)
    f0 = stonemask(w, x, timeaxis, f0)
    spectrogram = zeros(0, 0)
    if usecheaptrick
        spectrogram = cheaptrick(w, x, timeaxis, f0)
    else
        spectrogram = star(w, x, timeaxis, f0)
    end
    @test !any(isnan(spectrogram))
end

function test_cheaptrick(x, fs::Int=44100, period::Float64=5.0)
    println("test_cheaptrick: fs=$(fs), period=$(period)")
    test_envelope(x, fs, period, true)
end

function test_star(x, fs::Int=44100, period::Float64=5.0)
    println("test_star: fs=$(fs), period=$(period)")
    test_envelope(x, fs, period, false)
end

function test_platinum(x, fs::Int=44100, period::Float64=5.0)
    println("test_platinum: fs=$(fs), period=$(period)")
    w = World(fs, period)
    opt = DioOption(80.0, 640.0, 2, period, 4)
    f0, timeaxis = dio(w, x; opt=opt)
    f0 = stonemask(w, x, timeaxis, f0)
    spectrogram = cheaptrick(w, x, timeaxis, f0)
    residual = platinum(w, x, timeaxis, f0, spectrogram)
    @test !any(isnan(residual))
end

function test_aperiodicity(x, fs::Int=44100, period::Float64=5.0)
    println("test_aperiodicity: fs=$(fs), period=$(period)")
    w = World(fs, period)
    opt = DioOption(80.0, 640.0, 2, period, 4)
    f0, timeaxis = dio(w, x; opt=opt)
    f0 = stonemask(w, x, timeaxis, f0)
    aperiodicity = aperiodicityratio(w, x, f0, timeaxis)
    @test !any(isnan(aperiodicity))
end

# speech -> {f0, envelope, residual} -> speech
function test_synthesis(x::AbstractArray, fs::Int=44100, period::Float64=5.0,
                        usecheaptrick::Bool=false, tol::Float64=0.1)
    println("test_synthesis: fs=$(fs), period=$(period),
         usecheaptrick=$(usecheaptrick), tol=$(tol)")

    w = World(fs, period)
    opt = DioOption(80.0, 640.0, 2, period, 4)

    # Fundamental frequency (f0) estimation by DIO
    f0, timeaxis = dio(w, x; opt=opt)
    @test !any(isnan(f0))
    @test !any(isnan(timeaxis))

    # F0 re-estimation by StoneMask
    f0 = stonemask(w, x, timeaxis, f0)
    @test !any(isnan(f0))

    # Spectral envelope estimation
    spectrogram = zeros(0, 0)
    if usecheaptrick
        spectrogram = cheaptrick(w, x, timeaxis, f0)
    else
        spectrogram = star(w, x, timeaxis, f0)
    end
    @test !any(isnan(spectrogram))

    # Residual spectrogram estimation by Platinum
    residual = platinum(w, x, timeaxis, f0, spectrogram)
    @test !any(isnan(residual))

    # Sysnthesis from f0, spectral envelope and residual spectrogram.
    y_length = int((length(f0)-1)*period/1000 * fs) + 1
    y = synthesis(w, f0, spectrogram, residual, y_length)
    @test !any(isnan(y))

    minlen = min(length(x), length(y))
    errorrate = mean(abs(y[1:minlen]-x[1:minlen])) / maxabs(x[1:minlen])

    println("errorrate=$(errorrate)")

    @test errorrate < tol
end

# speech -> {f0, envelope, aperiodicity} -> speech
function test_aperiodicity_synthesis(x::AbstractArray, fs::Int=44100,
                                     period::Float64=5.0,
                                     usecheaptrick::Bool=true,
                                     tol::Float64=0.1)
    println("test_aperiodicity_synthesis: fs=$(fs), period=$(period),
         usecheaptrick=$(usecheaptrick), tol=$(tol)")

    w = World(fs, period)
    opt = DioOption(80.0, 640.0, 2, period, 4)

    # Fundamental frequency (f0) estimation by DIO
    f0, timeaxis = dio(w, x; opt=opt)
    @test !any(isnan(f0))
    @test !any(isnan(timeaxis))

    # F0 re-estimation by StoneMask
    f0 = stonemask(w, x, timeaxis, f0)
    @test !any(isnan(f0))

    # Spectral envelope estimation
    spectrogram = zeros(0, 0)
    if usecheaptrick
        spectrogram = cheaptrick(w, x, timeaxis, f0)
    else
        spectrogram = star(w, x, timeaxis, f0)
    end
    @test !any(isnan(spectrogram))

    # Aperiodicity ratio estimation
    aperiodicity = aperiodicityratio(w, x, f0, timeaxis)
    @test !any(isnan(aperiodicity))

    # Sysnthesis from f0, spectral envelope and aperiodicity ratio.
    y_length = int((length(f0)-1)*period/1000 * fs) + 1
    y = synthesis_from_aperiodicity(w, f0, spectrogram, aperiodicity, length(x))
    @test !any(isnan(y))

    minlen = min(length(x), length(y))
    errorrate = mean(abs(y[1:minlen]-x[1:minlen])) / maxabs(x[1:minlen])

    println("errorrate=$(errorrate)")

    @test errorrate < tol
end

# Read test data (male)
fpath = joinpath(Pkg.dir("WORLD"), "test", "data", "test16k.wav")
x, fs = wavread(fpath)
@assert size(x, 2) == 1 "The input data must be monoral."
@assert !any(isnan(x))
x = vec(x)
fs = int(fs)

for period in [5.0, 7.0, 10.0]
    test_dio(x, fs, period)
    test_stonemask(x, fs, period)
    test_cheaptrick(x, fs, period)
    test_star(x, fs, period)
    test_platinum(x, fs, period)
    test_aperiodicity(x, fs, period)
end

# Test WORLD speech decomposition and re-synthesis
for (period, tol) in ([5.0, 0.10], [7.0, 0.15], [10.0, 0.16])
    test_synthesis(x, fs, period, true, tol)
    test_synthesis(x, fs, period, false, tol)
end

println("WORLD decomposition and re-synthesis tests passed.")

# Test WORLD speech decomposition and re-synthesis with aperiodicity
for (period, tol) in ([5.0, 0.135], [7.0, 0.16], [10.0, 0.16])
    test_aperiodicity_synthesis(x, fs, period, true, tol)
    test_aperiodicity_synthesis(x, fs, period, false, tol)
end

println("WORLD decomposition with aperiodicity and re-synthesis tests passed.")

# spectrum envelop <-> mel-cepstrum conversion

let
    @assert fs == 16000
    w = World(fs, 5.0)
    f0, timeaxis = dio(w, x)
    f0 = stonemask(w, x, timeaxis, f0)
    spectrogram = cheaptrick(w, x, timeaxis, f0)
    spec = spectrogram[:,30]

    α = 0.41
    fftlen = get_fftsize_for_cheaptrick(fs)

    # check normalized mean squared error
    approximate_spec = mc2sp(sp2mc(spec, 25, α), α, fftlen)
    nmse25 = norm(log(spec) - log(approximate_spec))/norm(log(spec))
    @test nmse25 <= 0.06

    approximate_spec = mc2sp(sp2mc(spec, 30, α), α, fftlen)
    nmse30 = norm(log(spec) - log(approximate_spec))/norm(log(spec))
    @test nmse30 <= 0.05

    approximate_spec = mc2sp(sp2mc(spec, 40, α), α, fftlen)
    nmse40 = norm(log(spec) - log(approximate_spec))/norm(log(spec))
    @test nmse40 <= 0.03

    @test nmse25 > nmse30 > nmse40
end

# get_fftsize

let
    w1 = World(44100, 5.0)
    w2 = World(fs=44100, period=5.0)
    @test w1 == w2
end

for fs in [16000, 20000]
    s = get_fftsize_for_star(fs)
    c = get_fftsize_for_cheaptrick(fs)
    @test s == c == 1024
end

for fs in [44100, 48000]
    s = get_fftsize_for_star(fs)
    c = get_fftsize_for_cheaptrick(fs)
    @test s == c == 2048
end

# DioOption

let
    try DioOption(); catch @test false; end
    # f0loor
    @test_throws ArgumentError DioOption(-1,  100, 2.0, 5.0, 11)
    @test_throws ArgumentError DioOption(200, 100, 2.0, 5.0, 11)
    # channels in octave
    @test_throws ArgumentError DioOption(80.0, 640.0, -1.0, 5.0, 11)
    # period
    @test_throws ArgumentError DioOption(80.0, 640.0, 2.0, -1.0, 11)
    @test_throws ArgumentError DioOption(80.0, 640.0, 2.0, 0.0, 11)
    # speed
    try DioOption(80.0, 640.0, 2.0, 5.0, 1); catch @test false; end
    try DioOption(80.0, 640.0, 2.0, 5.0, 12); catch @test false; end
    @test_throws ArgumentError DioOption(80.0, 640.0, 2.0, 5.0, 0)
    @test_throws ArgumentError DioOption(80.0, 640.0, 2.0, 5.0, 13)
end
