using Base.Test
using SQLAlchemy

engine = createengine("sqlite:///:memory:")
metadata = MetaData()
users = Table("Users", metadata,
            Column("name", SQLString()),
            Column("age", SQLFloat()))
createall(metadata, engine)
db = connect(engine)
db(insert(users), name="Alice", age=27)
db(insert(users), name="Bob", age=31)
res = db(select([users])) |> fetchall
@test res[1][:name]|>get == "Alice"
@test res[2][2]|>get == 31

include("orm.jl")
