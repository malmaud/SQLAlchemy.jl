using SQLAlchemy

@table type User("Users")
    name::("name",UTF8String)
    age::("age", Float64)
    id::("id", Int, primary_key=true)
end

jon=User(name="Jon", age=27)
engine = createengine("sqlite:///:memory:", echo=true)
session=Session(engine)
createall(SQLAlchemy.metadata, engine)
