using ExpressionMatch

abstract AR

function sql_type_for_jl(sql_type)
    map = Dict(:UTF8String=>SQLString,
               :Int=>SQLInteger,
               :Float64=>SQLFloat,
               :String=>SQLString)
    map[sql_type]
end

const metadata = MetaData()

immutable TableMap
    table::Table
    columns::Dict{Symbol, String}
end

const table_map = Dict{Any, TableMap}()

@enum State Transient Pending Persistent Detached

macro table(desc)
    res = @match desc begin
        type T_(tablename_)
            fields__
        end -> (tablename, T, fields)
    end
    res == nothing && error("Invalid input to @table: $desc")
    tablename, T, fields = res
    new_fields = []
    columns = Column[]
    keys=[]
    name_map = Dict{Symbol, String}()
    field_types=Dict()
    for field in fields
        res = @match field begin
            (key_::(id_, t_, kwargs__)) -> (:hasname, key, id, t, kwargs)
            (key_::(t_, kwargs__)) -> (:noname, key, t, kwargs)
        end
        kind, res = res[1], res[2:end]
        if kind == :hasname
            key, id, t, kwargs = res
        elseif kind == :noname
            key, t, kwargs = res
            id = String(key)
        end
        name_map[key] = id
        sql_type = sql_type_for_jl(t)
        push!(new_fields, :($key::Nullable{$t}))
        field_types[key] = eval(t)
        push!(keys, key)
        kw = Dict()
        for arg in kwargs
            a,b = @match arg begin
                (a_=b_) -> (a,b)
            end
            kw[a] =b
        end
        push!(columns, Column(id, sql_type(); kw...))
    end
    quote
        type $(esc(T)) <: AR
            $(new_fields...)
            _state::State
            _session::Nullable{Session}
            _key::Nullable{Int}
        end

        function $(esc(T))(;kwargs...)
            d = Dict(kwargs)
            args = []
            field_types = $field_types
            for key in $keys
                if key ∉ keys(d)
                    # error("Must supply value for $key")
                    push!(args, Nullable{field_types[key]}())
                else
                    push!(args, Nullable(d[key]))
                end
            end
            push!(args, Transient)
            push!(args, Nullable{Session}())
            push!(args, Nullable{Int}())
            $(esc(T))(args...)
        end

        function Base.show(io::IO, t::$(esc(T)))
            print(io, $(QuoteNode(T)), ": ")
            names = ["$key=>$(field_show(t[key]))" for key in $keys]
            print(io, join(names, ", "))
        end



        SQLAlchemy.table_map[$(esc(T))] =
            SQLAlchemy.TableMap(SQLAlchemy.Table($tablename, metadata, ($columns)...),
                                $name_map)
    end
end

immutable ID
    key::Int
    table::DataType
end

function primarykey{T<:AR}(a::Type{T})
    tbl = table_map[a]
    pkeys = inspect(tbl.table)[:primary_key][:columns][:keys]()
    length(pkeys) == 0 && error("Wrapped class $(a) must have a primary key.")
    length(pkeys) > 1 && error("Composite primary keys not supported. Error on table $(a).")
    pkey = first(pkeys)
    for (k,v) in tbl.columns
        if v==pkey
            return k
        end
    end
    error("Internal error")
end

function ID{T<:AR}(t::T)
    pkeyname = primarykey(T)
    ID(t[pkeyname]|>get, T)
end

type Session
    db::Connection
    new_::Set{AR}
    dirty::Set{AR}
    deleted::Set{AR}
    identity_map::Dict{ID, AR}
end

Base.in{T<:AR}(ar::T, s::Session) = ID(ar) ∈ s
Base.in(id::ID, s::Session) = id ∈ s.identity_map

function setstate!(a::AR, state::State)
    a._state = state
end

function Base.push!(s::Session, a::AR)
    a._state == Persistent && a ∈ s && return s
    a._state == Pending && a ∈ s.new_ && return s
    setstate!(a, Pending)
    push!(s.new_, a)
    a._session = s
    s
end

Base.getindex(a::AR, field) = a.(field)

function Base.setindex!(a::AR, value, field)
    setindex!(a, Nullable(value), field)
end

function Base.setindex!(a::AR, value::Nullable, field)
    a.(field) = value
    if !isnull(a._session)
        session = get(a._session)
        push!(session.dirty, a)
    end
end

Session(engine::Engine) = Session(connect(engine), Set{AR}(), Set{AR}(),
                                  Set{AR}(), Dict{ID, AR}())

function Base.show(io::IO, s::Session)
    print(io, "Session")
end

type SessionQuery
    session::Session
    table::Type
    select::Select
end

function query{T<:AR}(session::Session, r::Type{T})
    SessionQuery(session, r, select([gettable(r)]))
end

function Base.all(s::SessionQuery)
    flush(s.session)
    recordset = s.session.db(s.select) |> fetchall
    ars = Vector{s.table}()
    for record in recordset.records
        push!(ars, push!(s.session, record, s.table))
    end
    ars
end

function Base.first(s::SessionQuery)
    flush(s.session)
    record = s.session.db(s.select) |> fetchone
    push!(s.session, record, s.table)
end

function fields(r::AR)
    column_map = table_map[typeof(r)].columns
    d = Dict()
    for (k, v) in column_map
        d[v] = r[k]
    end
    d
end

function sqlfields(r::AR)
    f = Dict()
    for (k, v) in fields(r)
        k = Symbol(k)
        if isnull(v)
            continue
        else
            f[k] = get(v)
        end
    end
    f
end

gettable{T<:AR}(::Type{T}) = table_map[T].table
gettable(r::AR) = gettable(typeof(r))

function Base.flush(s::Session)
    db = s.db
    for r in s.new_
        tbl = gettable(r)
        f = sqlfields(r)
        res = db(insert(tbl); f...)
        pkeys = res[:inserted_primary_key]
        isempty(pkeys) && error("Need primary key on $r")
        pkey = first(pkeys)
        r[primarykey(typeof(r))] = pkey
        s.identity_map[ID(r)] = r
        setstate!(r, Persistent)
    end
    empty!(s.new_)

    for r in s.dirty
        tbl = gettable(r)
        pkey = primarykey(typeof(r))
        stmt = update(tbl) |> where(tbl[pkey]==get(r[pkey]))
        db(stmt; sqlfields(r)...)
    end
    empty!(s.dirty)
end

Base.close(s::Session) = close(s.db)

function update!(a::AR, r::Record)
    column_map = table_map[typeof(a)].columns
    for (k,v) in column_map
        a[k] = r[Symbol(v)]
    end
    a
end

function Base.push!(s::Session, r::Record, tbl)
    pname = primarykey(tbl)
    sqlname = Symbol(table_map[tbl].columns[pname])
    id = ID(r[sqlname]|>get, tbl)
    if id ∈ keys(s.identity_map)
        a = s.identity_map[id]
    else
        a = tbl()
        a._state = Persistent
        s.identity_map[id] = a
    end
    update!(a, r)
end

function Base.getindex{T<:SQLAlchemy.AR}(::Type{T}, field)
    gettable(T)[field]
end

function Base.filter(clause::Wrapped)
    query->begin
        new_clause = query.select |> where(clause)
        SessionQuery(query.session, query.table, new_clause)
    end
end

function orderby(q::SessionQuery, field)
    SessionQuery(q.session, q.table, q.select |> orderby(field))
end

function Base.show{T<:AR}(io::IO, ::Type{T})
    table = table_map[T].table
    show(io, table)
end
