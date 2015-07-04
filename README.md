Wrapper over Python's [SQLAlchemy](http://www.sqlalchemy.org/) library

Basic usage
============

```julia
> engine = create_engine("sqlite:///:memory:")
> metadata = MetaData()
> users = Table("users", metadata, Column("name", String), Column("age", Real))
> conn = connect(engine)
> create_all(metadata, engine)
> execute(conn, insert(users) |> values(name="Alice", age=27.3))
> execute(conn, insert(users) |> values(name="Bob", age=45.1))
> res = execute(conn, select([users]) |> where(users[:age] > 30))
> fetchall(res)
1-element Array{Any,1}:
 PyObject (u'Bob', 45.0)
```
