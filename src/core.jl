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

type SQLFunc <: Wrapped
    o::PyObject
end

function func(name)
    arg->SQLFunc(sqlalchemy[:func][Symbol(name)][:__call__](unwrap(arg)))
end

func(name, arg) = func(name)(arg)

function Base.call(c::Connection, args...; kwargs...)
    execute(c, args...; kwargs...)
end

abstract SQLType <: Wrapped

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


for (jl_type, sql_type) in [(Integer, SQLInteger), (Bool, SQLBoolean),
                            (Real, SQLFloat), (String, SQLString)]
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
            m = $(QuoteNode(method))
            try
                val = unwrap(arg)[$(QuoteNode(method))](args...; kwargs...)
                $ret(val)
            catch err
                warn(err)
                x->$jlname(x, arg, args...; kwargs...)
            end
        end

        function $(esc(jlname))(args...; kwargs...)
            arg->$jlname(arg, args...; kwargs...)
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
@define_method Update where where Update
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
