export blockdiag, contract, cp_als, diagt, dirsum, dropdims, hosvd, innerprod, krontm, matten, mkrontm, mkrontv, mrank, mttkrp, neye, nrank, nvecs
export sthosvd, tenmat, tkron, ttm, ttt, ttv

"""
   blockdiag(X,Y)

Create block diagonal tensor where tensors X and Y are block elements. If X and Y are matrices, equal to blkdiag for sparse matrices.
"""
function blockdiag(X1::Array{T1,N},X2::Array{T2,N}) where {T1<:Number, T2<:Number, N}
  sz=tuple([size(X1)...]+[size(X2)...]...)
  Xd=zeros(promote_type(T1, T2), sz)
  R1=CartesianIndices(size(X1))
  I1=last(R1)
  R2=CartesianIndices(size(X2))
  for In in R1
    Xd[In]=X1[In]
  end
  for In in R2
    Xd[I1+In]=X2[In]
  end
  Xd
end
"""
   dirsum(X,Y)

Direct sum od tensors. Equal to blockdiag.
"""
dirsum(X1::Array{T1},X2::Array{T2}) where {T1<:Number,T2<:Number} = blockdiag(X1,X2)

"""
    contract(X,Y)
    contract(X,indX,Y,indY[,perm])
    contract(X::TensorCell)

Contracted product of tensors. Contract indX modes of array X to indY modes of array Y and permute the result by vector perm.
Default: indX=[ndims(X)], indY=[1].
"""
function contract(X1::Array{T1},ind1::Vector{Int},X2::Array{T2},ind2::Vector{Int},perm=[]) where {T1<:Number,T2<:Number}
    sz1=[size(X1)...]
    sz2=[size(X2)...]
    @assert(sz1[ind1]==sz2[ind2],"Dimension mismatch.")
    sz=[sz1[setdiff(1:ndims(X1),ind1)];sz2[setdiff(1:ndims(X2),ind2)]]
    Xres=reshape(transpose(tenmat(X1,row=ind1))*tenmat(X2,row=ind2),tuple(sz...))
    if perm!=[]
      Xres=permutedims(Xres,perm)
    end
    Xres
end
contract(X1::Array{T1},X2::Array{T2},ind::Vector{Int}) where {T1<:Number,T2<:Number} =contract(X1,ind,X2,ind)
contract(X1::Array{T1},ind1::Int,X2::Array{T2},ind2::Int,perm=[]) where {T1<:Number,T2<:Number} =contract(X1,[ind1],X2,[ind2],perm)
contract(X1::Array{T1},X2::Array{T2}) where {T1<:Number,T2<:Number} = contract(X1,ndims(X1),X2,1)



"""
    cp_als(X,R;init,tol,maxit,dimorder)

Compute a CP decomposition with R components of a tensor X .

## Arguments:
- `init` ∈ {MatrixCell,"rand","nvecs","eigs"}. Initial guess for factor matrices. If init="nvecs" (same as "eigs") initialize matrices with function nvecs.
- `tol`: Tolerance. Defualt: 1e-4.
- `maxit`: Maximal number of iterations. Default: 1000.
- `dimorder': Order of dimensions. Default: 1:ndims(A).
"""
function cp_als(X::Array{T},R::Integer;init="rand",tol=1e-4,maxit=1000,dimorder=[]) where {T<:Number}
    N=ndims(X)
    nr=norm(X)
    K=ktensor
    if length(dimorder) == 0
        dimorder=collect(1:N)
    end
    fmat=MatrixCell(undef,N)
    if isa(init,Vector) || isa(init,MatrixCell)
        @assert(length(init)==N,"Wrong number of initial matrices.")
        for n in dimorder[2:end]
            @assert(size(init[n])==(size(X,n),R),"$(n)-th initial matrix is of wrong size.")
            fmat[n]=init[n]
        end
    elseif init=="rand"
        [fmat[n]=rand(size(X,n),R) for n in dimorder[2:end]]
    elseif init=="eigs" || init=="nvecs"
        [fmat[n]=nvecs(X,n,R) for n in dimorder[2:end]]
    else
        error("Initialization method wrong.")
    end
    G = zeros(T,R,R,N); #initalize gramians
    for n in dimorder[2:end]
      if !isempty(fmat[n])
        G[:,:,n]=fmat[n]'*fmat[n]
      end
    end
    fit=0
    for k=1:maxit
        fitold=fit
        lambda=[]
        for n in dimorder
            fmat[n]=mttkrp(X,fmat,n)
            W=reshape(prod(G[:,:,setdiff(collect(1:N),n)],dims=3),Val(2))
            fmat[n]=fmat[n]/W
            if k == 1
                lambda = sqrt.(sum(fmat[n].^2,dims=1))[:] #2-norm
            else
                lambda = maximum(maximum(abs.(fmat[n]),dims=1),dims=1)[:] #max-norm
            end
            fmat[n] = fmat[n]./lambda'
            G[:,:,n] = fmat[n]'*fmat[n]
        end
        K=ktensor(lambda,fmat)
        if nr==0
            fit=norm(K)^2-2*innerprod(X,K)
        else
            nr_res=sqrt.(abs.(nr^2+norm(K)^2 .-2*innerprod(X,K)))
            fir=1 .-nr_res/nr
        end
        fitchange=abs.(fitold-fit)
        if k>1 && fitchange<tol
            break
        end
    end
    arrange!(K)
    fixsigns!(K)
    K
end

"""
    diagt(v[,dims])

Create a diagonal tensor for a given vector of diagonal elements. Generalization of diagm.
"""
function diagt(v::Vector{T}) where {T<:Number}
  N=length(v)
  sz=tuple(repeat([N],N,1)[:]...)
  D=zeros(T, sz)
  R=CartesianIndices(sz)
  In=first(R)
  for i=1:N
    D[In]=v[i]
    In=In+1*one(In)
  end
  D
end

function diagt(v::Vector{T},dims::Vector{D}) where {T<:Number,D<:Integer}
  Dt=diagt(v)
  sz=dims-[size(Dt)...]
  blockdiag(Dt,zeros(T,sz...))
end

"""
    hosvd(X; <keyword arguments>)

Higher-order singular value decomposition.

## Arguments:
- `X`: Tensor (multidimensional array) or ttensor.
- `method` ∈ {"svd","lanczos","randsvd"} Method for SVD. Default: "svd".
- `reqrank::Vector`: Requested mutlilinear rank. Optional.
- `eps_abs::Number/Vector`: Drop singular values (of mode-n matricization) below eps_abs. Default: 1e-8.
- `eps_rel::Number/Vector`: Drop singular values (of mode-n matricization) below eps_rel*sigma_1. Optional.
- `p::Integer`: Oversampling parameter. Defaul p=10.
"""
function hosvd(X::Array{T,N};method="svd",reqrank=[],eps_abs=[],eps_rel=[],p=10) where {T<:Number,N}
  fmat=MatrixCell(undef,N)

  reqrank=check_vector_input(reqrank,N,0)
  eps_abs=check_vector_input(eps_abs,N,1e-8)
  eps_rel=check_vector_input(eps_rel,N,0)

  for n=1:N
    Xn=float(tenmat(X,n))
    if method == "lanczos"
      fmat[n],S=lanczos(Xn,tol=eps_abs[n],reqrank=reqrank[n],p=p)
    elseif method == "randsvd"
      fmat[n],S=randsvd(Xn,tol=eps_abs[n],reqrank=reqrank[n],p=p)
    else
      fmat[n],S,V=svd(Xn)
    end
    if reqrank[n]!=0 && size(fmat[n],2)>reqrank[n]
      fmat[n]=fmat[n][:,1:reqrank[n]]
    else
      eps_rel[n] != 0 ? tol=eps_rel[n]*S[1] : tol=eps_abs[n]
      K=findall(x-> x>tol ? true : false,S)
      fmat[n]=fmat[n][:,K]
    end
  end
  ttensor(ttm(X,fmat,'t'),fmat)
end

"""
   innerprod(X,Y)
   innerprod(X::ttensor,Y::ttensor)
   innerprod(X::ktensor,Y::ktensor)

Inner product of two tensors.
"""
function innerprod(X1::Array{T1},X2::Array{T2}) where {T1<:Number,T2<:Number}
	@assert(size(X1) == size(X2),"Dimension mismatch")
	sum(X1.*conj(X2))
end

"""
   krontm(X,Y,M[,modes,t='n'])

Kronecker product of two tensors times matrix (n-mode product): (X ⊗ Y) x₁ M₁ x₂ M₂ x₃ ⋯ xₙ Mₙ.

## Arguments:
- `X::Array`
- `Y::Array`
- `M::Matrix/MatrixCell`
- `modes::Integer/Vector` : Modes for multiplication. Default: 1:length(M).
- `t='t'`: Transpose matrices from M.
"""
function krontm(X1::Array{T1,N},X2::Array{T2,N},M::MatrixCell,modes::Vector{D},t='n') where {T1<:Number,T2<:Number,D<:Integer,N}
  if t=='t'
    [M[n]=M[n]' for n=1:length(M)]
	end
	@assert(length(modes)<=length(M)<=N,"Dimension mismatch.")
  sz=[size(X1)...].*[size(X2)...]
  R=copy(sz)
  if length(modes) != length(M)
    M=M[modes] #discard matrices not needed for multiplication
  end
  for n=1:length(modes)
      R[modes[n]]=size(M[n],1) #vector of rₖ
  end
  #Order of multiplication - if tkron(X₁,X₂) is i₁ × i₂ × ... × iₙ and Mₖ are rₖ × iₖ, sort by largest possible dimension reduction iₖ-rₖ
  p=sortperm(sz[modes]-R[modes],rev=true)
  M=M[p]
  modes=modes[p]
  @assert(sz[modes[1]] == size(M[1],2),"Dimensions mismatch")
  Xn=copy(mkrontv(X1,X2,copy(M[1]'),modes[1],'t')')
  sz[modes[1]]=size(M[1],1)
  X=matten(Xn,modes[1],sz)
  for n=2:length(M)
	   @assert(sz[modes[n]] == size(M[n],2),"Dimensions mismatch")
     Xn=tenmat(X,modes[n])
	   sz[modes[n]]=size(M[n],1)
	   X=matten(M[n]*Xn,modes[n],sz)
	end
#  end
  X
end
krontm(X1::Array{T1},X2::Array{T2},M::Matrix{T3},n::Integer,t='n') where {T1<:Number,T2<:Number,T3<:Number}=krontm(X1,X2,[M],[n],t)
krontm(X1::Array{T1},X2::Array{T2},M::MatrixCell,t::Char) where {T1<:Number,T2<:Number}=krontm(X1,X2,M,1:length(M),t)
krontm(X1::Array{T1},X2::Array{T2},M::MatrixCell) where {T1<:Number,T2<:Number}=krontm(X1,X2,M,1:length(M))
krontm(X1::Array{T1},X2::Array{T2},M::MatrixCell,modes::AbstractRange{D},t::Char) where {T1<:Number,T2<:Number,D<:Integer}=krontm(X1,X2,M,collect(modes),t)
krontm(X1::Array{T1},X2::Array{T2},M::MatrixCell,modes::AbstractRange{D}) where {T1<:Number,T2<:Number,D<:Integer}=krontm(X1,X2,M,collect(modes))
function krontm(X1::Array{T1,N},X2::Array{T2,N},M::MatrixCell,n::Integer,t='n') where {T1<:Number,T2<:Number,N}
 	if n>0
 		krontm(X1,X2,M[n],n,t)
 	else
 		modes=setdiff(1:N,-n)
 		krontm(X1,X2,M,modes,t)
 	end
end
#If array of matrices isn't defined as MatrixCell, but as M=[M1,M2,...,Mn]:
krontm(X1::Array{T1,N},X2::Array{T2,N},M::Array{Matrix{T3}},modes::Vector{D},t='n') where {T1<:Number,T2<:Number,T3<:Number,D<:Integer,N}=krontm(X1,X2,MatrixCell(M),modes,t)
krontm(X1::Array{T1},X2::Array{T2},M::Array{Matrix{T3}},t::Char) where {T1<:Number,T2<:Number,T3<:Number}=krontm(X1,X2,MatrixCell(M),t)
krontm(X1::Array{T1},X2::Array{T2},M::Array{Matrix{T3}}) where {T1<:Number,T2<:Number,T3<:Number}=krontm(X1,X2,MatrixCell(M))
krontm(X1::Array{T1},X2::Array{T2},M::Array{Matrix{T3}},modes::AbstractRange{D},t::Char) where {T1<:Number,T2<:Number,T3<:Number,D<:Integer}=krontm(X1,X2,MatrixCell{M},modes,t)
krontm(X1::Array{T1},X2::Array{T2},M::Array{Matrix{T3}},modes::AbstractRange{D}) where {T1<:Number,T2<:Number,T3<:Number,D<:Integer}=krontm(X1,X2,MatrixCell{M},modes)
krontm(X1::Array{T1,N},X2::Array{T2,N},M::Array{Matrix{T3}},n::Integer,t='n') where {T1<:Number,T2<:Number,T3<:Number,N}=krontm(X1,X2,MatrixCell{M},n,t)


"""
    matten(A,n,dims)
    matten(A,R,C,dims)

Fold matrix A into a tensor of dimension dims by mode n or by row and column vectors R and C.
"""
function matten(A::Matrix{T},n::Integer,dims::Vector{D}) where {T<:Number,D<:Integer}
	@assert(dims[n]==size(A,1),"Dimensions mismatch")
	m = setdiff(1:length(dims), n)
	@assert prod(dims[m])==size(A,2)
	X = reshape(A,[dims[n];dims[m]]...)
	permutedims(X,invperm([n;m]))
end

function matten(A::Matrix{T},row::Vector{D},col::Vector{D},dims::Vector{D}) where {T<:Number,D<:Integer}
	@assert(prod(dims[row])==size(A,1) && prod(dims[col])==size(A,2),"Dimensions mismatch")
	X = reshape(A,[dims[row];dims[col]]...)
	permutedims(X,invperm([row;col]))
end

"""
    mkrontv(X,Y,v,n,t='n')

Matricized Kronecker product of tensors X and Y times vector v (n-mode multiplication): (X ⊗ Y)ₙv.
If t='t', transpose matricized Kronecker product: (X ⊗ Y)ᵀₙv.
If v is a matrix, multiply column by column.
"""
function mkrontv(X1::Array{T1,N},X2::Array{T2,N},v::Vector{T3},n::Integer,t='n') where {T1<:Number,T2<:Number,T3<:Number,N}
  I1=size(X1)
  I2=size(X2)
  kronsize=tuple(([I1...].*[I2...])...);
  ind=setdiff(1:N,n) #all indices but n
  X1n=tenmat(X1,n);
  X2n=tenmat(X2,n);
  perfect_shuffle=Int[ [2*k-1 for k=1:N-1]; [2*k for k=1:N-1] ]
  if t=='n'
    @assert(length(v) == prod(kronsize[ind]),"Vector is of inapropriate size.")
    tenshape=vec([[I2[ind]...] [I1[ind]...]]');
    vperm=permutedims(reshape(v,tenshape...),perfect_shuffle);
    vec(X2n*reshape(vperm,size(X2n,2),size(X1n,2))*X1n')
  elseif t=='t'
    @assert(length(v) == kronsize[n],"Vector is of inapropriate size.")
    if I1[n]*prod(I2)+prod(I1)*prod(I2[ind]) > I2[n]*prod(I1)+prod(I2)*prod(I1[ind])
      W=(X2n'*reshape(v,size(X2n,1),size(X1n,1)))*X1n
    else
      W=X2n'*(reshape(v,size(X2n,1),size(X1n,1))*X1n)
    end
    tenshape=[[I2[ind]...];[I1[ind]...]];
    vec(permutedims(reshape(W,tenshape...),invperm(perfect_shuffle)))
    end
end

#Matricized Kronecker product times matrix - column by column.
function mkrontv(X1::Array{T1,N},X2::Array{T2,N},M::Matrix{T3},n::Integer,t='n') where {T1<:Number,T2<:Number,T3<:Number,N}
  if sort(collect(size(vec(M))))[1]==1
    return mkrontv(A,B,vec(M));
  end
  I1=size(X1);
  I2=size(X2);
  kronsize=([I1...].*[I2...]);
  ind=setdiff(1:N,n) #all indices but n
  if t=='n'
    Mprod=zeros(promote_type(T1,T2,T3),kronsize[n],size(M,2))
  else
    Mprod=zeros(promote_type(T1,T2,T3),prod(kronsize[ind]),size(M,2))
  end
  for i=1:size(M,2)
    Mprod[:,i]=mkrontv(X1,X2,M[:,i],n,t);
  end
  Mprod
end
function mkrontm(X1::Array{T1,N},X2::Array{T2,N},M::Matrix{T3},n::Integer,t='n') where {T1<:Number,T2<:Number,T3<:Number,N}
  @warn "Function mkrontm is depricated. Use mkrontv."
  mkrontv(X1,X2,M,n,t)
end

"""
    mrank(X[,tol])
    mrank(X::ttensor[,tol])

Multilinear rank of a tensor with optionally given tolerance.
"""
function mrank(X::Array{T,N}) where {T<:Number,N}
   ntuple(n->nrank(X,n),N)
end
function mrank(X::Array{T,N},tol::Number) where {T<:Number,N}
   ntuple(n->nrank(X,n,tol),N)
end

"""
    mttkrp(X,M,n)
    mttkrp(X::ttensor,M,n)
    mttkrp(X::ktensor,M,n)

Mode-n matricized tensor X times Khatri-Rao product of matrices from M (except nth) in reverse order.
"""
function mttkrp(X::Array{T,N},M::MatrixCell,n::Integer) where {T<:Number,N}
  @assert(N-1<=length(M)<=N,"Wrong number of matrices")
  if length(M)==N-1  #if nth matrix not defined
    push!(M,M[end])
    [M[m]=M[m-1] for m=N-1:-1:n+1]
  end
  modes=setdiff(1:N,n)
  sz=[size(X)...]
  K=size(M[modes[1]],2)
  @assert(!any(map(Bool,[size(M[m],2)-K for m in modes])),"Matrices must have the same number of columns.")
  @assert(!any(map(Bool,[size(M[m],1)-sz[m] for m in modes])),"Matrices are of wrong size.")
  Xn=tenmat(X,n)
  Xn*khatrirao(reverse(M[modes]))
end
mttkrp(X::Array{T1,N},M::Array{Matrix{T2}},n::Integer) where {T1<:Number,T2<:Number,N}=mttkrp(X,MatrixCell(M),n)

"""
    neye(dims)

Identity tensor of a given dimension. Generalization of eye.
"""
function neye(dims::Vector{D}) where {D<:Integer}
  dims=tuple(dims...)
  A=zeros(dims) # always gives Array{Float64}
  R=CartesianIndices(dims)
  Ifirst=first(R)
  Iend=last(R)
  while Ifirst<=Iend
      A[Ifirst]=1
      Ifirst=Ifirst+1*one(Ifirst)
  end
  A
end
function neye(d1,d2...)
  if isempty(d2)
    return neye([d1...])
  end
  dims=[d1]
  for d in d2
    push!(dims,d)
  end
  neye(dims)
end
function neye(d::Integer;order=0)
  @assert(order>0,"Wrong input.")
  neye(repeat([d],order,1)[:])
end

"""
    nrank(X,n[,tol])
    nrank(X::ttensor,n[,tol])

Rank of the n-mode matricization of a tensor X (n-rank).
"""
function nrank(X::Array{T},n::Integer) where {T<:Number}
  rank(tenmat(X,n))
end
function nrank(X::Array{T},n::Integer,tol::Number) where {T<:Number}
  rank(tenmat(X,n),tol)
end

"""
    nvecs(X,n,r=0;flipsign=false,svds=false)
    nvecs(X::ttensor,n,r=0;flipsign=false)
    nvecs(X::ktensor,n,r=0;flipsign=false)

Computes the r leading singular vectors of mode-n matricization of a tensor X.
Works with XₙXₙᵀ.

## Arguments:
- `flipsign=true`: Make the largest magnitude element be positive.
- `svds=true`: Use svds on Xₙ rather than eigs on XₙXₙᵀ.
"""
function nvecs(X::Array{T},n::Integer,r=0;flipsign=false,svds=false) where {T<:Number}
  if r==0
    r=size(X,n)
  end
  Xn=tenmat(X,n)
  if svds
    #U=svds(Xn,nsv=r)[1][:U]
    #if size(U,2)<r
      U=svdfact(Xn)[:U][1:r]
    #end
  else
    G=Symmetric(Xn*Xn') #Gramian
    #U=eigs(G,nev=r,which=:LM)[2] #has bugs!
    #if size(U,2)<r
       U=eigen(G).vectors[:,end:-1:end-r+1]
    #end
  end
  if flipsign
      maxind = findmax(abs.(U),1)[2]
      for i = 1:r
          ind=ind2sub(size(U),maxind[i])
          if U[ind...] < 0
             U[:,ind[2]] = U[:,ind[2]] * -1
          end
      end
  end
  U
end

#Squeeze all singleton dimensions. **Documentation in Base.jl.
function dropdims(A::Array{T}) where {T<:Number}
  sz=size(A)
  sdims=findall(sz.==1) #singleton dimensions
  dropdims(A,dims=tuple(sdims...))
end

"""
    sthosvd(X,reqrank,p)

Sequentially truncated HOSVD of a tensor X of predifined rank and processing order p.
"""
function sthosvd(X::Array{T,N};reqrank=[],order=[],tol=1e-8) where {T<:Number,N}
    if order==[]
        order=collect(1:N)
    end
    @assert(N==length(order),"Dimensions mismatch")
    if reqrank!=[]
        @assert(N==length(reqrank),"Dimensions mismatch")
    end
	sz=[size(X)...]
	fmat=MatrixCell(undef,N)
	for n in order
		Xn=tenmat(X,n)
		U,S,V=svd(Xn)
        if reqrank!=[]
            fmat[n]=U[:,1:reqrank[n]]
		    Xn=Diagonal(S[1:reqrank[n]])*V'[1:reqrank[n],:]
            sz[n]=reqrank[n]
        else
            K=findall(x-> x>tol ? true : false,S)
            fmat[n]=U[:,K]
		    Xn=Diagonal(S[K])*V[:,K]'
            sz[n]=length(K)
        end
		X=matten(Xn,n,sz)
	end
	ttensor(X,fmat)
end

"""
    tenmat(X,n)
    tenmat(X,row=[],col=[])
    tenmat(X::ttensor,n)
    tenmat(X::ktensor,n)

Mode-n matricization of a tensor or matricization by row and column vectors R and C.
"""
function tenmat(X::Array{T,N},n::Integer) where {T<:Number,N}
	@assert(n<=ndims(X),"Mode exceedes number of dimensions")
	sz=size(X)
	m=setdiff(1:N,n)
    if [n;m]!=collect(1:N)
        X=permutedims(X,[n;m])
    end
	reshape(X,sz[n],prod(sz[m]))
end

function tenmat(X::Array{T,N};row=[],col=[]) where {T<:Number,N}
    @assert(row!=[] || col!=[],"Al least one of row and col needs to be specified.")
    if row!=[] && col!=[]
        @assert(sort([row;col])==collect(1:N),"Incorrect mode partitioning.")
    elseif row==[]
        @assert(!(false in [c in collect(1:N) for c in col]),"Incorrect modes.")
        if isa(col,Integer)
            col=[col]
        end
        row=collect(1:N)
        deleteat!(row,sort(col))
    else
        @assert(!(false in [r in collect(1:N) for r in row]),"Incorrect modes.")
        if isa(row,Integer)
            row=[row]
        end
        col=collect(1:N)
        deleteat!(col,sort(row))
    end
	sz=size(X)
    J=prod(sz[row]);K=prod(sz[col])
    if [row;col]!=collect(1:N)
        X=permutedims(X,[row;col])
    end
	reshape(X,J,K)
end

"""
    tkron(X,Y)

Kronecker product of two tensors X and Y. Direct generalization of Kronecker product of matrices.
"""
function tkron(X1::Array{T1,N},X2::Array{T2,N}) where {T1<:Number,T2<:Number,N}
  if N<3
    return kron(X1,X2)
  end
  s1=size(X1)
  s2=size(X2)
  Xk=zeros(promote_type(T1,T2),s1.*s2)
  R1=CartesianIndices(s1)
  R2=CartesianIndices(s2)
  Il=last(R2)
  i=0
  for I1 in R1
    for I2 in R2
      Xk[I2+ewprod((I1-1*one(I1)),Il)]=X1[I1]*X2[I2]
    end
    i+=1
  end
  Xk
end

"""
    ttm(X,M[,modes,t='n'])
    ttm(X::ttensor,M[,modes,t='n'])

Tensor times matrix (n-mode product):  X x₁ M₁ x₂ M₂ x₃ ⋯ xₙ Mₙ
Default modes: 1:length(M).
If t='t', transpose matrices from M.
"""
function ttm(X::Array{T,N},A::MatrixCell,modes::Vector{D},t='n') where {T<:Number,D<:Integer,N}
  M=deepcopy(A)
  if t=='t'
    [M[n]=M[n]' for n=1:length(M)]
  end
  @assert(length(modes)<=length(M),"Too few matrices.")
  @assert(length(M)<=N,"Too many matrices.")
  sz=[size(X)...]
  if length(modes) < length(M)
    M=M[modes] #discard matrices not needed for multiplication
  end
  R=copy(sz)
  for n=1:length(modes)
    R[modes[n]]=size(M[n],1) #vector of rₖ
  end
  #Order of multiplication - if X is i₁ × i₂ × ... × iₙ and Mₖ is rₖ × iₖ, sort by largest possible dimension reduction iₖ-rₖ
  p=sortperm(sz[modes]-R[modes],rev=true)
  M=M[p]
  modes=modes[p]
  for n=1:length(M)
	 @assert(sz[modes[n]] == size(M[n],2),"Dimensions mismatch")
     Xn=tenmat(X,modes[n])
	 sz[modes[n]]=size(M[n],1)
	 X=matten(M[n]*Xn,modes[n],sz)
  end
  X
end
ttm(X::Array{T1},M::Matrix{T2},n::Integer,t='n') where {T1<:Number,T2<:Number}=ttm(X,Matrix[M],[n],t)
ttm(X::Array{T},M::MatrixCell,t::Char) where {T<:Number}=ttm(X,M,1:length(M),t)
ttm(X::Array{T},M::MatrixCell) where {T<:Number}=ttm(X,M,1:length(M))
ttm(X::Array{T},M::MatrixCell,R::AbstractRange{D},t::Char) where {T<:Number,D<:Integer}=ttm(X,M,collect(R),t)
ttm(X::Array{T},M::MatrixCell,R::AbstractRange{D}) where {T<:Number,D<:Integer}=ttm(X,M,collect(R))
function ttm(X::Array{T,N},M::MatrixCell,n::Integer,t='n') where {T<:Number,N}
	if n>0
		ttm(X,M[n],n,t)
	else
		modes=setdiff(1:N,-n)
		ttm(X,M,modes,t)
	end
end
#If array of matrices isn't defined as MatrixCell, but as M=[M1,M2,...,Mn]:
ttm(X::Array{T1,N},M::Array{Matrix{T2}},modes::Vector{D},t='n') where {T1<:Number,T2<:Number,D<:Integer,N}=ttm(X,MatrixCell(M),modes,t)
ttm(X::Array{T1},M::Array{Matrix{T2}},t::Char) where {T1<:Number,T2<:Number}=ttm(X,MatrixCell(M),t)
ttm(X::Array{T1},M::Array{Matrix{T2}}) where {T1<:Number,T2<:Number}=ttm(X,MatrixCell(M))
ttm(X::Array{T1},M::Array{Matrix{T2}},R::AbstractRange{D},t::Char) where {T1<:Number,T2<:Number,D<:Integer}=ttm(X,MatrixCell{M},R,t)
ttm(X::Array{T1},M::Array{Matrix{T2}},R::AbstractRange{D}) where {T1<:Number,T2<:Number,D<:Integer}=ttm(X,MatrixCell(M),R)
ttm(X::Array{T1,N},M::Array{Matrix{T2}},n::Integer,t='n') where {T1<:Number,T2<:Number,N}=ttm(X,MatrixCell(M),n,t)

"""
    ttv(X,Y)

Outer product of two tensors.
"""
function ttt(X1::Array{T1},X2::Array{T2}) where {T1<:Number,T2<:Number}
  sz=tuple([[size(X1)...];[size(X2)...]]...);
  Xprod=vec(X1)*vec(X2)';
  reshape(Xprod,sz)
end

"""
    ttv(X,V[,modes])

Tensor times vectors (n-mode product):  X x₁ V₁ x₂ V₂ x₃ ⋯ xₙ Vₙ.
Default modes: 1:length(M).
"""
function ttv(X::Array{T,N},V::VectorCell,modes::Vector{D}) where {T<:Number,D<:Integer,N}
  remmodes=setdiff(1:N,modes)'
  if N > 1
    X=permutedims(X,[remmodes modes'])
  end
  sz=size(X)
  if length(modes) < length(V)
    V=V[modes]
  end
  M=N
  for n=length(modes):-1:1
    X=reshape(X,prod(sz[1:M-1]),sz[M])
    X=X*V[n]
    M-=1
  end
  if M>0
    X=reshape(X,sz[1:M])
  end
  X
end
ttv(X::Array{T1,N},v::Vector{T2},n::Integer) where {T1<:Number,T2<:Number,N}=ttv(X,Vector[v],[n])
ttv(X::Array{T,N},V::VectorCell) where {T<:Number,N}=ttv(X,V,collect(1:length(V)))
function ttv(X::Array{T,N},V::VectorCell,n::Integer) where {T<:Number,N}
	if n>0
		ttv(X,V[n],n)
	else
		modes=setdiff(1:N,-n)
		ttv(X,V,modes)
	end
end
#If array of vectors isn't defined as VectorCell, but as V=[v1,v2,...,vn]:
ttv(X::Array{T1,N},V::Array{Vector{T2}},modes::Vector{D}) where {T1<:Number,T2<:Number,D<:Integer,N}=ttv(X,VectorCell(V),modes)
ttv(X::Array{T1,N},V::Array{Vector{T2}}) where {T1<:Number,T2<:Number,N}=ttv(X,VectorCell(V))
ttv(X::Array{T1,N},V::Array{Vector{T2}},n::Integer) where {T1<:Number,T2<:Number,N}=ttv(X,VectorCell(V),n)
