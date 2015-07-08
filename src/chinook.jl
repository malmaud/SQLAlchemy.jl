using Compat

function loadchinook()
    path = joinpath(Pkg.dir("SQLAlchemy"), "deps", "data", "Chinook_Sqlite.sqlite")
    tables = ["Artist", "Album", "Playlist", "PlaylistTrack", "Track",
              "MediaType", "Genre", "InvoiceLine", "Invoice", "Employee",
              "Customer"]
    engine = createengine("sqlite:///$path")
    meta = MetaData(engine)
    schema = Dict{UTF8String, Table}()
    for table in tables
        schema[table] = Table(table, meta, autoload=true)
    end
    db = connect(engine)
    db, schema
end

