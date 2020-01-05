# This file constains the Buffer for data buffering.

import Base: getindex, setindex!, size, read, isempty, setproperty!, fill!, length, eltype

##### Buffer modes
abstract type BufferMode end
abstract type CyclicMode <: BufferMode end 
abstract type LinearMode <: BufferMode end  
struct Cyclic <: CyclicMode end 
struct Normal <: LinearMode end
struct Lifo <: LinearMode end 
struct Fifo <: LinearMode end 


##### Buffer
mutable struct Buffer{M<:BufferMode, T}
    data::Vector{T}
    index::Int 
    state::Symbol 
    callbacks::Vector{Callback}
    id::UUID
    Buffer{M}(::Type{T}, ln::Int) where {M, T} = new{M, Union{Missing, T}}(fill!(Vector{Union{Missing,T}}(undef, ln),
         missing), 1, :empty, Callback[], uuid4())
end
Buffer(::Type{T}, ln::Int) where T = Buffer{Cyclic}(T, ln)
Buffer{M}(ln::Int) where M = Buffer{M}(Float64, ln)
Buffer(ln::Int) = Buffer(Float64, ln)

show(io::IO, buf::Buffer)= print(io, 
    "Buffer(mode:$(mode(buf)), eltype:$(eltype(buf)), length:$(length(buf)), index:$(buf.index), state:$(buf.state))")


##### Buffer info.
mode(buf::Buffer{M, T}) where {M, T} = M
eltype(buf::Buffer{M, T}) where {M, T} = T

##### AbstractArray interface.
eltype(buf::Buffer) = eltype(buf.data)
length(buf::Buffer) = length(buf.data)
size(buf::Buffer) = size(buf.data)
getindex(buf::Buffer, idx::Vararg{Int, N}) where N = buf.data[idx...]
setindex!(buf::Buffer, val, inds::Vararg{Int, N}) where N = (buf.data[inds...] = val)

##### Buffer state control and check.
isempty(buf::Buffer) = buf.state == :empty
isfull(buf::Buffer) = buf.state == :full
function setproperty!(buf::Buffer, name::Symbol, val::Int)
    if name == :index
        val < 1 && error("Buffer index cannot be less than 1.")
        setfield!(buf, name, val)
        if val == 1
            buf.state = :empty
        elseif val > size(buf.data, 1)
            buf.state = :full
        else
            buf.state = :nonempty
        end
    end
end

##### Writing into buffers
resetindex(buf::Buffer) = setfield!(buf, :index, %(buf.index, size(buf.data, 1)))
checkindex(buf::Buffer) = isfull(buf) && resetindex(buf)
writelinear(buf::Buffer{M, T}, val) where {M, T} = 
    isfull(buf) ? (@warn "Buffer is full.") : (buf[buf.index] = val; buf.index +=1)
writecylic(buf::Buffer{M, T}, val) where {M, T} = (buf[buf.index] = val; buf.index += 1; checkindex(buf))
writeinto(buf::Buffer{M, T}, val) where{M<:LinearMode, T} = writelinear(buf, val)
writeinto(buf::Buffer{M, T}, val) where{M<:CyclicMode, T} = writecylic(buf, val)
write!(buf::Buffer{M, T}, val) where {M, T} = (writeinto(buf, val); buf.callbacks(buf); val) 
write!(buf::Buffer{M, T}, val::AbstractArray{Missing}) where {M, T} = write!(buf, missing)

fill!(buf::Buffer{M, T}, val::T) where {M, T} = foreach(i -> write!(buf, val), 1 : length(buf))

##### Reading from buffers
readfrom(buf::Buffer{M, T}) where {M<:Union{Normal, Cyclic}, T} = buf.data[buf.index - 1]
function readfrom(buf::Buffer{M, T}) where {M<:Fifo, T}
    val = buf.data[1]
    buf.data .= circshift(buf.data, -1)
    buf.data[end] = missing
    buf.index -= 1
    val
end
function readfrom(buf::Buffer{M, T}) where {M<:Lifo, T}
    val = buf.data[end]
    buf.data[end] = missing
    buf.index -= 1
    val
end
function read(buf::Buffer) 
    isempty(buf) && error("Buffer is empty")
    val = readfrom(buf)
    buf.callbacks(buf)
    val
end

##### Accessing buffer data
function content(buf::Buffer; flip::Bool=true)
    val = buf[1 : buf.index - 1]
    flip ? reverse(val, dims=1) : val
end

snapshot(buf::Buffer) = buf.data

##### Calling buffers.
(buf::Buffer)() = read(buf)