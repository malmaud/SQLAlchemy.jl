module SQLAlchemy

export Table, Column, Integer, String, MetaData, Engine

using PyCall
@pyimport sqlalchemy

abstract Wrapped
unwrap(x)=x
unwrap(x::Wrapped)=x.o

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

function create_engine(args...; kwargs...)
    Engine(sqlalchemy.create_engine(args...; kwargs...))
end


end
