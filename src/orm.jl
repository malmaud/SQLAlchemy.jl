using MacroTools

Base.getindex(n::Nullable) = n.value

abstract AR

const metadata = MetaData()

immutable TableMap
    table::Table
    columns::Dict{Symbol, String}
    relations::Dict{Symbol, Dict{Symbol, Any}}
end

const table_map = Dict{Any, TableMap}()

function columnname(tbl, sqlname)
    for (k,v) in table_map[tbl].columns
        if v==sqlname
            return k
        end
    end
end

@enum State Transient Pending Persistent Detached
@enum ARSetState Unloaded Loaded

type ARSet{T<:AR}
    R::Vector{T}
    state::Symbol
    parent::AR
    column::Symbol
    state::ARSetState
    ARSet(parent, column) = new(T[], :unloaded, parent, column, Unloaded)
end


function Base.getindex(s::ARSet, idx)
    s.R[idx]
end

Base.endof(s::ARSet) = endof(s.R)
Base.length(s::ARSet) = length(s.R)

function Base.push!(s::ARSet, r::AR)
    push!(s.R, r)
    parent = s.parent
    if parent._state ∈ (Pending, Persistent)
        push!(parent._session[], r)
    end
    if parent._state == Persistent
        setforeign!(r, parent, s.column)
    end
    s
end

macro table(desc)
    success = @capture desc begin
        type T_
            tablename_
            fields__
        end
    end
    success || error("Invalid input to @table: $desc")
    new_fields = []
    columns = Column[]
    keys=[]
    name_map = Dict{Symbol, String}()
    field_types=Dict()
    relations = Dict{Symbol, Dict{Symbol, Any}}()
    for field in fields
        res = @match field begin
            (key_::(id_, t_, kwargs__)) => (:hasname, key, id, t, kwargs)
            (key_::(t_, kwargs__)) => (:noname, key, t, kwargs)
            (key_::relation(t_, kwargs__)) => (:relation, key, t, kwargs)
        end
        kind, res = res[1], res[2:end]
        if kind == :relation
            key, foreign_t, kwargs = res
            push!(new_fields, :($key::ARSet{$(esc(foreign_t))}))
            push!(keys, (:foreign, key, foreign_t))
            relations[key] = Dict{Symbol, Any}()
            for arg in kwargs
                @capture arg begin
                    a_ = b_
                end
                relations[key][a]=b
            end
        else
            if kind == :hasname
                key, id, t, kwargs = res
            elseif kind == :noname
                key, t, kwargs = res
                id = String(key)
            else
                error("Field $field not understood")
            end
            name_map[key] = id
            field_types[key] = convert(JuliaType, eval(t))
            # field_name = field_types[key].name.name
            field_name = field_types[key].name.name
            push!(new_fields, :($key::Nullable{$field_name}))

            push!(keys, (:field, key))
            kw = Dict()
            for arg in kwargs
                @capture arg begin
                    a_ = b_
                end
                kw[a] =b
            end
            push!(columns, Column(id, eval(t); kw...))
        end
    end
    defaults=[]
    for (idx, val) in enumerate(keys)
        kind = val[1]
        val = val[2:end]
        if kind == :field
            key = val[1]
            push!(defaults, :(this.$key=Nullable{$(field_types[key])}()))
        elseif kind == :foreign
            key, t = val
            push!(defaults, :(this.$key=ARSet{$(esc(t))}(this, $(QuoteNode(key)))))
        end
    end

    quote
        type $(esc(T)) <: AR
            $(new_fields...)
            _state::State
            _session::Nullable{Session}
            _key::Nullable{Int}

            function $(esc(T))(;kwargs...)
                this = new()
                $(defaults...)
                for (key, val) in kwargs
                    this.(key) = Nullable(val)
                end
                this._state = Transient
                this._session = Nullable{Session}()
                this._key = Nullable{Int}()
                this
            end
        end



        # function Base.show(io::IO, t::$(esc(T)))
        #     print(io, $(QuoteNode(T)), ": ")
        #     names = ["$key=>$(field_show(t[key]))" for key in $keys]
        #     print(io, join(names, ", "))
        # end



        SQLAlchemy.table_map[$(esc(T))] =
            SQLAlchemy.TableMap(SQLAlchemy.Table($tablename, metadata, ($columns)...),
                                $name_map, $relations)
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

macro typelift(f)
    quote
        $(esc(f))(x::AR) = $f(typeof(x))
    end
end

@typelift primarykey


function ID{T<:AR}(t::T)
    pkeyname = primarykey(T)
    ID(t[pkeyname][], T)
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
    if state == Persistent
        relations = table_map[typeof(a)].relations
        for relation in keys(relations)
            s = a[relation]
            for r in s.R
                setforeign!(r, a, s.column)
            end
        end
    end
    a
end


function dirty!(r::AR)
    if !isnull(r._session)
        push!(r._session[].dirty, r)
    end
end

function joincolumns(child_t, parent_t, column)
    table = gettable(child_t)
    parent_table = gettable(parent_t)
    columns = table.o[:columns][:items]()
    for (name, column) in columns
        for key in column[:foreign_keys]
            if key[:column][:table] == parent_table.o
                return columnname(child_t, name), columnname(parent_table, key[:column][:name])
            end
        end
    end
end

function setforeign!(child, parent, column)
    child_key, parent_key = joincolumns(typeof(child), typeof(parent), column)
    child[child_key] = parent[parent_key]
    child
end

function foreignkeys{T<:AR}(::Type{T})
    table_map[T].relations |> keys
end
@typelift foreignkeys

function Base.push!(s::Session, a::AR)
    a._state == Persistent && a ∈ s && return s
    a._state == Pending && a ∈ s.new_ && return s
    setstate!(a, Pending)
    push!(s.new_, a)
    a._session = s
    for keyname in foreignkeys(a)
        for r in a[keyname].R
            push!(s, r)
        end
    end
    s
end

function ensureloaded!{T}(session::Session, a::ARSet{T})
    a.state == Loaded && return a
    parent_t = typeof(a.parent)
    child_key, parent_key = joincolumns(T, parent_t, :a)
    a.R = query(session, T)|>filter(parent_t[parent_key] == T[child_key])|>all
    a.state = Loaded
    a
end


function Base.getindex(a::AR, field)
    val = a.(field)
    if a._state == Persistent && isa(val, ARSet)
        ensureloaded!(a._session[], val)
    end
    val
end

function Base.setindex!(a::AR, value, field)
    setindex!(a, Nullable(value), field)
end

function Base.setindex!(a::AR, value::Nullable, field)
    a.(field) = value
    dirty!(a)
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

function query{T<:AR}(session::Session, ::Type{T})
    SessionQuery(session, T, select([gettable(T)]))
end

function Base.join{T<:AR}(::Type{T})
    query->begin
        t1 = table_map[query.table].table
        t2 = table_map[T].table
        clause = query.select |> selectfrom(join(t1, t2))
        SessionQuery(query.session, query.table, clause)
    end
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
            f[k] = v[]
        end
    end
    f
end

gettable{T<:AR}(::Type{T}) = table_map[T].table
@typelift gettable

function Base.flush(s::Session)
    db = s.db
    new_ = [s.new_...]
    # for r in s.new_
    while !isempty(s.new_)
        r = pop!(s.new_)
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
        pkey = primarykey(r)
        stmt = update(tbl) |> where(tbl[pkey]==r[pkey][])
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
    id = ID(r[sqlname][], tbl)
    if id ∈ keys(s.identity_map)
        a = s.identity_map[id]
    else
        a = tbl()
        a._state = Persistent
        s.identity_map[id] = a
    end
    update!(a, r)
end

function Base.getindex{T<:SQLAlchemy.AR}(::Type{T}, jl_field)
    sql_field = table_map[T].columns[jl_field]
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

# function Base.show{T<:AR}(io::IO, ::Type{T})
#     table = table_map[T].table
#     show(io, table)
# end
