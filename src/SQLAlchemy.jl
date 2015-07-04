module SQLAlchemy

using PyCall
@pyimport sqlalchemy

export Table, Column, Integer, String, MetaData, Engine
export create_engine, select, text, connect
export create_all, insert, values, compile, connect, execute, fetchone, fetchall, where, select_from, and_, order_by, alias, join
export SQLString, SQLInteger, SQLBoolean, SQLDate, SQLDateTime, SQLEnum, SQLFloat, SQLInterval, SQLNumeric, SQLText, SQLTime, SQLUnicode, SQLUnicodeText

abstract Wrapped
unwrap(x)=x
unwrap(x::Wrapped)=x.o
unwrap(x::Union{Tuple,Vector}) = map(unwrap, x)

function unwrap_kw(x)
    [(v[1], unwrap(v[2])) for v in x]
end

macro wrap_type(typename)
    quote
        type $(esc(typename)) <: Wrapped
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

macro wrap_sql_type(typenames...)
    e = Expr(:block)
    for typename in typenames
        sqlname = Symbol(string("SQL",typename))
        q = quote
            type $(esc(sqlname)) <: Wrapped
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

type Other <: Wrapped
    o::PyObject
end

macro define_method(typename, method, ret)
    e = quote
        function $method(arg::$typename, args...; kwargs...)
            args = unwrap(args)
            kwargs = unwrap_kw(kwargs)
            val = unwrap(arg)[$(QuoteNode(method))](args...; kwargs...)
            $ret(val)
        end

        function $method(args...; kwargs...)
            arg->$method(arg, args...; kwargs...)
        end
    end
    esc(e)
end

macro define_top(method, ret)
    e = quote
        function $method(args...; kwargs...)
            args = unwrap(args)
            kwargs = unwrap_kw(kwargs)
            val = sqlalchemy.$method(args...; kwargs...)
            $ret(val)
        end
    end
    esc(e)
end

@define_method MetaData create_all Other
@define_method Table insert Insert
@define_method Insert values Insert
@define_method Insert compile Insert
@define_method Engine connect Connection
@define_method Connection execute ResultProxy
@define_method ResultProxy fetchone identity
@define_method ResultProxy fetchall identity
@define_method ResultProxy Base.close identity
@define_method Select where Select
@define_method Select select_from Select
@define_method Select and_ Select
@define_method Select order_by Select
@define_method Table alias Other
@define_method Table join Other

function Base.print(io::IO, w::Wrapped)
    print(io, unwrap(w)[:__str__]())
end

function Base.show(io::IO, w::Wrapped)
    print(io, unwrap(w)[:__repr__]())
end

@define_top create_engine Engine
@define_top select Select
@define_top text Select

getindex(t::Table, column_name) = Column(unwrap(t)[:c][Symbol(column_name)])

for (op, py_op) in zip([:(==), :(>), :(>=), :(<), :(<=), :(!=)], [:__eq__, :__gt__, :__ge__, :__lt__, :__le__, :__ne__])
    @eval function $op(c1::Column, c2::Union{Column, AbstractString, Number})
        BinaryExpression(unwrap(c1)[$(QuoteNode(py_op))](unwrap(c2)))
    end
end


end
