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
> db(insert(users, name="Alice", age=27.3))
> db(insert(users, name="Bob", age=45.1))
> db(select([users]) |> where(users[:age] > 30)) |> fetchall
(name => Bob, age => 45.1)
```
