s=SQLAlchemy
engine=s.create_engine("sqlite:///:memory:")
metadata=s.MetaData()
users=s.Table("Users", metadata, s.Column("name", s.String()))
s.create_all(metadata, engine)
ins=s.values(s.insert(users), name="Jon")
conn=s.connect(engine)
res=s.execute(conn,ins)

