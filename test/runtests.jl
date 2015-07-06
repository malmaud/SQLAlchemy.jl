s=SQLAlchemy
engine=s.create_engine("sqlite:///:memory:")
metadata=s.MetaData()
users=s.Table("Users", metadata, s.Column("name", s.SQLString()))
s.create_all(metadata, engine)
ins=s.insert(users) |> s.values(name="jon")
conn=s.connect(engine)
res=s.execute(conn,ins)

