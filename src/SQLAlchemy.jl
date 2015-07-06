module SQLAlchemy

using PyCall
using NamedTuples

@pyimport sqlalchemy

export Table, Column, Integer, String, MetaData, Engine
export createengine, select, text, connect
export createall, insert, values, compile, connect, execute, fetchone, fetchall, where, selectfrom, and, orderby, alias, join, groupby, having
export SQLString, SQLInteger, SQLBoolean, SQLDate, SQLDateTime, SQLEnum, SQLFloat, SQLInterval, SQLNumeric, SQLText, SQLTime, SQLUnicode, SQLUnicodeText

abstract Wrapped
unwrap(x)=x
unwrap(x::Wrapped)=x.o
unwrap(x::Union{Tuple,Vector}) = map(unwrap, x)

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
                new(sqlalchemy.$typename(args...; kwargs...))
            end
            function $(esc(typename))(o::PyObject)
                new(o)
            end
        end
    end
end

@wrap_type Table
@wrap_type Column
@wrap_type MetaData
@wrap_type Engine
@wrap_type Insert
@wrap_type Connection
@wrap_type Select
@wrap_type ResultProxy
@wrap_type BinaryExpression

function Base.call(c::Connection, args...; kwargs...)
    execute(c, args...; kwargs...)
end

macro wrap_sql_type(typenames...)
    e = Expr(:block)
    for typename in typenames
        sqlname = Symbol(string("SQL",typename))
        q = quote
            immutable $(esc(sqlname)) <: Wrapped
                o::PyObject
                function $(esc(sqlname))(args...; kwargs...)
                    args = unwrap(args)
                    kwargs = unwrap_kw(kwargs)
                    new(sqlalchemy.$typename(args...; kwargs...))
                end
                $(esc(sqlname))(o::PyObject) = new(o)
            end
        end
        push!(e.args, q)
    end
    e
end

@wrap_sql_type String Integer Boolean Date DateTime Enum Float Interval Numeric Text Time Unicode UnicodeText


for (jl_type, sql_type) in [(Integer, SQLInteger), (Bool, SQLBoolean), (Real, SQLFloat), (String, SQLString)]
    unwrap{T<:jl_type}(::Type{T}) = unwrap(sql_type())
end

immutable Other <: Wrapped
    o::PyObject
end

macro define_method(typename, method, jlname, ret)
    quote
        function $(esc(jlname))(arg::$typename, args...; kwargs...)
            args = unwrap(args)
            kwargs = unwrap_kw(kwargs)
            val = unwrap(arg)[$(QuoteNode(method))](args...; kwargs...)
            $ret(val)
        end

        function $(esc(jlname))(args...; kwargs...)
            arg->$method(arg, args...; kwargs...)
        end
    end
end

macro define_top(method, jlname, ret)
    quote
        function $(esc(jlname))(args...; kwargs...)
            args = unwrap(args)
            kwargs = unwrap_kw(kwargs)
            val = sqlalchemy.$method(args...; kwargs...)
            $ret(val)
        end
    end
end

# immutable Record <: Wrapped
#     o :: PyObject
# end

# index_to_py(x::Number) = x+1
# index_to_py(x) = x

# function Base.getindex(r::Record, key)
#     r.o[:__getitem__](index_to_py(key))
# end

function makerecord(pyo)
    keys = pyo[:keys]()
    vals = pyo[:values]()
    e= :(@NT)
    for (key, val) in zip(keys, vals)
        push!(e.args, :($(Symbol(key))=>$val))
    end
    eval(e)
end

function makerecords(records)
    res = map(makerecord, records)
    isempty(res) && return res
    convert(Vector{typeof(res[1])}, res)
end

@define_method MetaData create_all createall Other
@define_method Table insert insert Insert
@define_method Insert values Base.values Insert
@define_method Insert compile compile Insert
@define_method Engine connect Base.connect Connection
@define_method Connection execute execute ResultProxy
@define_method Select where where Select
@define_method Select select_from selectfrom Select
@define_method Select and_ and Select
@define_method Select order_by orderby Select
@define_method Select group_by groupby Select
@define_method Select having having Select
@define_method Table alias alias Other
@define_method ResultProxy fetchone fetchone makerecord
@define_method ResultProxy fetchall fetchall makerecords

function Base.join(t1::Table, t2::Table; kwargs...)
    Select(t1.o[:join](t2; kwargs...))
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

getindex(t::Table, column_name) = Column(unwrap(t)[:c][Symbol(column_name)])

for (op, py_op) in zip([:(==), :(>), :(>=), :(<), :(<=), :(!=)], [:__eq__, :__gt__, :__ge__, :__lt__, :__le__, :__ne__])
    @eval function $op(c1::Column, c2::Union{Column, AbstractString, Number})
        BinaryExpression(unwrap(c1)[$(QuoteNode(py_op))](unwrap(c2)))
    end
end


end
