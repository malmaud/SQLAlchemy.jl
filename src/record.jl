using PyCall

const COLUMN_NAMES = Dict{Int, Vector{UTF8String}}()

immutable Record{T}
    fields::T
    columns_idx::Int
end
column_names(r) = COLUMN_NAMES[r.columns_idx]
Base.getindex(r::Record, idx::Integer) = r.fields[idx]

function Base.getindex(r::Record, idx::String)
    num_idx = findfirst(column_names(r), idx)
    r[num_idx]
end

Base.getindex(r::Record, idx::Symbol) = r[string(idx)]

function field_show(field)
    if isnull(field)
        "NULL"
    else
        sprint(show, get(field))
    end
end

function Base.show(io::IO, r::Record)
    columns = column_names(r)
    names = ["$column=>$(field_show(field))" for (column, field) in zip(columns, r.fields)]
    print(io, join(names, ", "))
end

function Record(pyo::PyObject)
    keys = pyo[:keys]()
    values = pyo[:values]()
    idx = convert(Int, hash(keys))
    COLUMN_NAMES[idx] = keys
    for i in eachindex(values)
        if values[i] == nothing
            values[i] = Nullable()  # TODO make correct type
        else
            values[i] = Nullable(values[i])
        end
    end
    Record((values...), idx)
end

immutable RecordSet
    records::Vector{Record}
    columns_idx::Int
end

function Base.getindex(s::RecordSet, idx::Integer)
    s.records[idx]
end

function Base.getindex(s::RecordSet, idx)
    RecordSet(s.records[idx], s.columns_idx)
end

function RecordSet(records)
    if isempty(records)
        RecordSet(Record{()}, 0)
    else
        records = map(Record, records)
        RecordSet(records, records[1].columns_idx)
    end
end

Base.endof(rs::RecordSet) = endof(rs.records)

function Base.show(io::IO, rs::RecordSet)
    limit = min(length(rs.records), 10)
    for i=1:limit
        print(io, rs.records[i])
        if i<limit
            print(io, "\n")
        end
    end
    if length(rs.records) > limit
        println(io, "...")
    end
end
