module SQLAlchemy

export Table, Column, Integer, String, MetaData, Engine
export create_engine, select, text
export create_all, insert, values, compile, connect, execute, fetchone, fetchall, where, select_from, and_, order_by, alias, join


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
                args = map(unwrap, args)
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
@wrap_type Integer
@wrap_type String
@wrap_type MetaData
@wrap_type Engine
@wrap_type Insert
@wrap_type Connection
@wrap_type Select
@wrap_type ResultProxy

type Other <: Wrapped
    o::PyObject
end

macro define_method(typename, method, ret)
    e = quote
        function $method(arg::$typename, args...; kwargs...)
            args = unwrap(args)
            @show args
            kwargs = unwrap_kw(kwargs)
            val = unwrap(arg)[$(QuoteNode(method))](args...; kwargs...)
            $ret(val)
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

@define_top create_engine Engine
@define_top select Select
@define_top text Select



end
