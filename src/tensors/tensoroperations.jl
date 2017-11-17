# Add support for TensorOperations.jl
function similar_from_indices(T::Type, p1::IndexTuple, p2::IndexTuple, t::AbstractTensorMap)
    s = codomain(t) ⊗ dual(domain(t))
    cod = s[map(n->tensor2spaceindex(t,n), p1)]
    dom = dual(s[map(n->tensor2spaceindex(t,n), reverse(p2))])
    return similar(t, T, cod←dom)
end
function similar_from_indices(T::Type, oindA::IndexTuple, oindB::IndexTuple, p1::IndexTuple, p2::IndexTuple, tA::AbstractTensorMap{S}, tB::AbstractTensorMap{S}) where {S<:IndexSpace}
    sA = codomain(tA) ⊗ dual(domain(tA))
    sB = codomain(tB) ⊗ dual(domain(tB))
    s = sA[map(n->tensor2spaceindex(tA,n), oindA)] ⊗ sB[map(n->tensor2spaceindex(tB,n), oindB)]
    cod = s[p1]
    dom = dual(s[reverse(p2)])
    return similar(tA, T, cod←dom)
end

scalar(t::AbstractTensorMap{S,0,0}) where {S<:IndexSpace} = block(t, one(sectortype(S)))[1,1]

function add!(α, tsrc::AbstractTensorMap{S}, β, tdst::AbstractTensorMap{S,N₁,N₂}, p1::IndexTuple{N₁}, p2::IndexTuple{N₂}) where {S,N₁,N₂}
    # TODO: Frobenius-Schur indicators!, and fermions!
    @boundscheck begin
        all(i->space(tsrc, p1[i]) == space(tdst,i), 1:N₁) || throw(SpaceMismatch("tsrc = $(codomain(tsrc))←$(domain(tsrc)), tdst = $(codomain(tdst))←$(domain(tdst)), p1 = $(p1), p2 = $(p2)"))
        all(i->space(tsrc, p2[i]) == space(tdst,N₁+i), 1:N₂) || throw(SpaceMismatch("tsrc = $(codomain(tsrc))←$(domain(tsrc)), tdst = $(codomain(tdst))←$(domain(tdst)), p1 = $(p1), p2 = $(p2)"))
    end

    pdata = (p1...,p2...)
    if sectortype(S) == Trivial
        if iszero(β)
            fill!(tdst, β)
        end
        if β != 1
            @inbounds axpby!(α, permutedims(tsrc[], pdata), β, tdst[])
        else
            @inbounds axpy!(α, permutedims(tsrc[], pdata), tdst[])
        end
    else
        if iszero(β)
            fill!(tdst, β)
        elseif β != 1
            scale!(tdst, β)
        end
        for (f1,f2) in fusiontrees(tsrc)
            for ((f1′,f2′), coeff) in permute(f1, f2, p1, p2)
                @inbounds axpy!(α*coeff, permutedims(tsrc[f1,f2], pdata), tdst[f1′,f2′])
            end
        end
    end
    return tdst
end

function contract!(α, A::AbstractTensorMap{S}, B::AbstractTensorMap{S}, β, C::AbstractTensorMap{S,N₁,N₂}, oindA::IndexTuple, cindA::IndexTuple, oindB::IndexTuple, cindB::IndexTuple, p1::IndexTuple{N₁}, p2::IndexTuple{N₂}) where {S<:IndexSpace,N₁,N₂}
    A′ = permuteind(A, oindA, cindA)
    B′ = permuteind(B, cindB, oindB)
    if α == 1 && β == 0 && length(oindA) == N₁ && p1 == ntuple(n->n, StaticLength(N₁)) && p2 == ntuple(n->(N₁+n), StaticLength(N₂))
        A_mul_B!(C, A′, B′)
    else
        add!(α, A′ * B′, β, C, p1, p2)
    end
    return C
end

# Compatibility layer for working with the `@tensor` macro from TensorOperations
TensorOperations.numind(t::AbstractTensorMap) = numind(t)
TensorOperations.numind(T::Type{<:AbstractTensorMap}) = numind(T)

function TensorOperations.similar_from_indices(T::Type, p1::IndexTuple, p2::IndexTuple, t::AbstractTensorMap, V::Type{<:Val})
    if V == Val{:N}
        similar_from_indices(T, p1, p2, t)
    else
        p1 = map(n->adjointtensorindex(t,n), p1)
        p2 = map(n->adjointtensorindex(t,n), p2)
        similar_from_indices(T, p1, p2, adjoint(t))
    end
end
function TensorOperations.similar_from_indices(T::Type, oindA::IndexTuple, oindB::IndexTuple, p1::IndexTuple, p2::IndexTuple, tA::AbstractTensorMap{S}, tB::AbstractTensorMap{S}, VA::Type{<:Val}, VB::Type{<:Val}) where {S}
    if VA == Val{:N} && VB == Val{:N}
        similar_from_indices(T, oindA, oindB, p1, p2, tA, tB)
    elseif VA == Val{:N} && VB == Val{:C}
        oindB = map(n->adjointtensorindex(tB,n), oindB)
        similar_from_indices(T, oindA, oindB, p1, p2, tA, adjoint(tB))
    elseif VA == Val{:C} && VB == Val{:N}
        oindA = map(n->adjointtensorindex(tA,n), oindA)
        similar_from_indices(T, oindA, oindB, p1, p2, adjoint(tA), tB)
    else
        oindA = map(n->adjointtensorindex(tA,n), oindA)
        oindB = map(n->adjointtensorindex(tB,n), oindB)
        similar_from_indices(T, oindA, oindB, p1, p2, adjoint(tA), adjoint(tB))
    end
end

TensorOperations.scalar(t::AbstractTensorMap) = scalar(t)

function TensorOperations.add!(α, tsrc::AbstractTensorMap{S}, V::Type{<:Val}, β, tdst::AbstractTensorMap{S,N₁,N₂}, p1::IndexTuple, p2::IndexTuple) where {S,N₁,N₂}
    p = (p1..., p2...)
    if V == Val{:N}
        pl = ntuple(n->p[n], StaticLength(N₁))
        pr = ntuple(n->p[N₁+n], StaticLength(N₂))
        add!(α, tsrc, β, tdst, pl, pr)
    else
        pl = ntuple(n->adjointtensorindex(tsrc, p[n]), StaticLength(N₁))
        pr = ntuple(n->adjointtensorindex(tsrc, p[N₁+n]), StaticLength(N₂))
        add!(α, adjoint(tsrc), β, tdst, pl, pr)
    end
    return tdst
end

function TensorOperations.contract!(α, tA::AbstractTensorMap{S}, VA::Type{<:Val}, tB::AbstractTensorMap{S}, VB::Type{<:Val}, β, tC::AbstractTensorMap{S,N₁,N₂}, oindA::IndexTuple, cindA::IndexTuple, oindB::IndexTuple, cindB::IndexTuple, p1::IndexTuple, p2::IndexTuple) where {S,N₁,N₂}
    p = (p1..., p2...)
    pl = ntuple(n->p[n], StaticLength(N₁))
    pr = ntuple(n->p[N₁+n], StaticLength(N₂))
    if VA == Val{:N} && VB == Val{:N}
        contract!(α, tA, tB, β, tC, oindA, cindA, oindB, cindB, pl, pr)
    elseif VA == Val{:N} && VB == Val{:C}
        oindB = map(n->adjointtensorindex(tB,n), oindB)
        cindB = map(n->adjointtensorindex(tB,n), cindB)
        contract!(α, tA, adjoint(tB), β, tC, oindA, cindA, oindB, cindB, pl, pr)
    elseif VA == Val{:C} && VB == Val{:N}
        oindA = map(n->adjointtensorindex(tA,n), oindA)
        cindA = map(n->adjointtensorindex(tA,n), cindA)
        contract!(α, adjoint(tA), tB, β, tC, oindA, cindA, oindB, cindB, pl, pr)
    else
        oindA = map(n->adjointtensorindex(tA,n), oindA)
        cindA = map(n->adjointtensorindex(tA,n), cindA)
        oindB = map(n->adjointtensorindex(tB,n), oindB)
        cindB = map(n->adjointtensorindex(tB,n), cindB)
        contract!(α, adjoint(tA), adjoint(tB), β, tC, oindA, cindA, oindB, cindB, pl, pr)
    end
    return tC
end