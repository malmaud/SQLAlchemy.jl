using PyCall
using Compat

const sqlalchemy=pyimport("sqlalchemy")
const inspection=pyimport("sqlalchemy.inspection")

abstract Wrapped
Base.getindex(w::Wrapped, key) = w.o[key]

unwrap(x)=x
unwrap(x::Wrapped)=x.o
unwrap(x::Union(Tuple,Vector)) = map(unwrap, x)

function unwrap_kw(x)
    [(_[1], unwrap(_[2])) for _ in x]
end

macro wrap_type(typename)
    quote
        immutable $(esc(typename)) <: Wrapped
            o::PyObject

            function $(esc(typename))(args...; kwargs...)
                args = unwrap(args)
                kwargs = unwrap_kw(kwargs)
                new(sqlalchemy[$(QuoteNode(typename))](args...; kwargs...))
            end

            function $(esc(typename))(o::PyObject)
                new(o)
            end
        end
    end
end

@wrap_type BinaryExpression
@wrap_type Column
@wrap_type Connection
@wrap_type Delete
@wrap_type Engine
@wrap_type Insert
@wrap_type MetaData
@wrap_type ResultProxy
@wrap_type Select
@wrap_type Table
@wrap_type UnaryExpression
@wrap_type Update
@wrap_type ForeignKey

type SQLFunc <: Wrapped
    o::PyObject
end

type DelayedSQLFunc
    name::Symbol
    DelayedSQLFunc(name) = new(Symbol(name))
end

function Base.show(io::IO, d::DelayedSQLFunc)
    print(io, d.name, "(...)")
end

function Base.call(d::DelayedSQLFunc, args...; kwargs...)
    args = unwrap(args)
    kwargs = unwrap_kw(kwargs)
    SQLFunc(sqlalchemy[:func][d.name][:__call__](args...; kwargs...))
end

func(name) = DelayedSQLFunc(name)
func(name, arg) = func(name)(arg)

function Base.call(c::Connection, args...; kwargs...)
    execute(c, args...; kwargs...)
end

abstract SQLType <: Wrapped
abstract JuliaType

macro wrap_sql_type(typenames...)
    e = Expr(:block)
    for typename in typenames
        sqlname = Symbol(string("SQL", typename))
        q = quote
            immutable $(esc(sqlname)) <: SQLType
                o::PyObject
                function $(esc(sqlname))(args...; kwargs...)
                    args = unwrap(args)
                    kwargs = unwrap_kw(kwargs)
                    new(sqlalchemy[$(QuoteNode(typename))](args...; kwargs...))
                end
                $(esc(sqlname))(o::PyObject) = new(o)
            end
        end
        push!(e.args, q)
    end
    e
end

@wrap_sql_type String Integer Boolean Date DateTime Enum Float Interval Numeric Text Time Unicode UnicodeText

const jl_sql_type_map = Dict([(Int, SQLInteger), (Bool, SQLBoolean),
                            (Float64, SQLFloat), (UTF8String, SQLString)])


for (jl_type, sql_type) in jl_sql_type_map
    unwrap{T<:jl_type}(::Type{T}) = unwrap(sql_type())
end

function Base.convert(::Type{JuliaType}, s::Wrapped)
    if isa(s, ForeignKey) return Int end
    for (k,v) in jl_sql_type_map
        if isa(s, v) return k end
    end
    error("No corresponding Julia type for $s")
end

function Base.convert(::Type{SQLType}, s)
    for (k,v) in jl_sql_type_map
        if s <: k
            return v()
        end
    end
    error("No corresponding SQL type for $s")
end


immutable Other <: Wrapped
    o::PyObject
end

type DelayedFunction
    args
    kwargs
    fname
end

function Base.show(io::IO, d::DelayedFunction)
    print(io, d.fname, "(")
    print(io, "_, ")
    isempty(d.args) || print(io, join(d.args, ", "))
    isempty(d.kwargs) || print(io, ";", join(d.kwargs, ", "))
    print(io, ")")
end

function Base.call(d::DelayedFunction, arg::Wrapped)
    d.fname(arg, d.args...; d.kwargs...)
end

macro define_method(typename, method, jlname, ret)
    quote
        function $(esc(jlname))(arg::$typename, args...; kwargs...)
            args = unwrap(args)
            kwargs = unwrap_kw(kwargs)
            m = $(QuoteNode(method))
            try
                val = unwrap(arg)[$(QuoteNode(method))](args...; kwargs...)
                $ret(val)
            catch err
                args = [arg, args...]
                DelayedFunction(args, kwargs, $jlname)
            end
        end

        function $(esc(jlname))(args...; kwargs...)
            DelayedFunction(args, kwargs, $jlname)
        end
    end
end

macro define_top(method, jlname, ret)
    quote
        function $(esc(jlname))(args...; kwargs...)
            args = unwrap(args)
            kwargs = unwrap_kw(kwargs)
            val = sqlalchemy[$(QuoteNode(method))](args...; kwargs...)
            $ret(val)
        end
    end
end

@define_method MetaData create_all createall Other
@define_method Table insert insert Insert
@define_method Insert values Base.values Insert
@define_method Insert compile compile Insert
@define_method Engine connect Base.connect Connection
@define_method Connection execute execute ResultProxy
@define_method Connection close Base.close identity
@define_method Update where where Update
@define_method Select where where Select
@define_method Select select_from selectfrom Select
@define_method Select and_ and Select
@define_method Select order_by orderby Select
@define_method Select group_by groupby Select
@define_method Select having having Select
@define_method Select distinct distinct Select
@define_method Select limit limit Select
@define_method Select offset offset Select
@define_method Table alias alias Other
@define_method Table delete delete Delete
@define_method Table update update Update
@define_method ResultProxy fetchone fetchone Record
@define_method ResultProxy fetchall fetchall RecordSet
@define_method Delete where where Delete

@define_method SQLFunc label label SQLFunc

function Base.join(t1::Table, t2::Table; kwargs...)
    Select(t1.o[:join](unwrap(t2); kwargs...))
end

function Base.print(io::IO, w::Wrapped)
    print(io, unwrap(w)[:__str__]())
end

function Base.show(io::IO, w::Wrapped)
    print(io, unwrap(w)[:__repr__]())
end

@define_top create_engine createengine Engine
@define_top select Base.select Select
@define_top text text Select
@define_top desc desc UnaryExpression
@define_top asc asc UnaryExpression

function inspect(w::Wrapped)
    Other(inspection[:inspect](unwrap(w)))
end

Base.getindex(t::Table, column_name) = Column(unwrap(t)[:c][Symbol(column_name)])


for (op, py_op) in zip([:(==), :(>), :(>=), :(<), :(<=), :(!=)],
                       [:__eq__, :__gt__, :__ge__, :__lt__, :__le__, :__ne__])
    @eval function $op(c1::Column, c2::Union{Column, AbstractString, Number})
        BinaryExpression(unwrap(c1)[$(QuoteNode(py_op))](unwrap(c2)))
    end
end
