Wrapper over Python's [SQLAlchemy](http://www.sqlalchemy.org/) library.


Basic usage
============

```julia
> using SQLAlchemy
> engine = createengine("sqlite:///:memory:")
> metadata = MetaData()
> users = Table("users", metadata, Column("name", String), Column("age", Real))
> db = connect(engine)
> createall(metadata, engine)
> db(insert(users) |> values(name="Alice", age=27.3))
> db(insert(users) |> values(name="Bob", age=45.1))
> res = db(select([users]) |> where(users[:age] > 30))
> fetchall(res)

1-element Array{NamedTuples._NT_nameage{UTF8String,Float64},1}:
(name => Bob, age => 45.1)
```
