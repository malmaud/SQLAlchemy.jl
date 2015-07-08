Wrapper over Python's [SQLAlchemy](http://www.sqlalchemy.org/) library.

Currently only wraps the [SQL Expression Language](http://docs.sqlalchemy.org/en/rel_1_0/core/tutorial.html) component (also called the "Core"), not the object-relational component.


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
> records = db(select([users]) |> where(users[:age] > 30)) |> fetchall
(name => Bob, age => 45.1)
> records[1][:age] 
Nullable(45.1)
> typeof(records[1])
SQLAlchemy.Record{Tuple{Nullable{UTF8String}, Nullable{Int64}}}
```

More advanced querying
===========

SQLAlchemy ships the [Chinook](https://chinookdatabase.codeplex.com/wikipage?title=Chinook_Schema&referringTitle=Home) sqlite database as learning tool and a conveience function ``loadchinook` to open a sqlite connection to it.

In this example, we'll see which artist has the most albums in the Chinook db.

```julia
> using SQLAlchemy
> db, schema = loadchinook()
# Let's look at part of the Album and Artist tables
> albums = Table("Album", schema, autoload=true)  # autoload causes the table schema to be read from the database
```

```
Table('Album', 
MetaData(bind=Engine(sqlite:////Users/malmaud/.julia/v0.4/SQLAlchemy/deps/data/Chinook_Sqlite.sqlite)), 
Column('AlbumId', INTEGER(), table=<Album>, primary_key=True, nullable=False), 
Column('Title', NVARCHAR(length=160), table=<Album>, nullable=False), 
Column('ArtistId', INTEGER(), ForeignKey(u'Artist.ArtistId'), table=<Album>, nullable=False), 
schema=None)
```

```julia
> artists = Table("Artist", schema, autoload=true)
```

```
Table('Artist', 
MetaData(bind=Engine(sqlite:////Users/malmaud/.julia/v0.4/SQLAlchemy/deps/data/Chinook_Sqlite.sqlite)), 
Column('ArtistId', INTEGER(), table=<Artist>, primary_key=True, nullable=False), 
Column('Name', NVARCHAR(length=120), table=<Artist>), 
schema=None)
```

```julia
> db(select([artists])) |> fetchall
```

```
ArtistId=>1, Name=>"AC/DC"
ArtistId=>2, Name=>"Accept"
ArtistId=>3, Name=>"Aerosmith"
ArtistId=>4, Name=>"Alanis Morissette"
ArtistId=>5, Name=>"Alice In Chains"
ArtistId=>6, Name=>"Antônio Carlos Jobim"
ArtistId=>7, Name=>"Apocalyptica"
ArtistId=>8, Name=>"Audioslave"
ArtistId=>9, Name=>"BackBeat"
ArtistId=>10, Name=>"Billy Cobham"
```

```julia
> db(select([albums])) |> fetchall
```

```
AlbumId=>1, Title=>"For Those About To Rock We Salute You", ArtistId=>1
AlbumId=>2, Title=>"Balls to the Wall", ArtistId=>2
AlbumId=>3, Title=>"Restless and Wild", ArtistId=>2
AlbumId=>4, Title=>"Let There Be Rock", ArtistId=>1
AlbumId=>5, Title=>"Big Ones", ArtistId=>3
AlbumId=>6, Title=>"Jagged Little Pill", ArtistId=>4
AlbumId=>7, Title=>"Facelift", ArtistId=>5
AlbumId=>8, Title=>"Warner 25 Anos", ArtistId=>6
AlbumId=>9, Title=>"Plays Metallica By Four Cellos", ArtistId=>7
AlbumId=>10, Title=>"Audioslave", ArtistId=>8
```

```julia
> db(select([artists[:Name],
             func("count", albums[:Title]) |> label("# of albums")]) |>
     selectfrom(join(artists, albums)) |>
     groupby(albums[:ArtistId]) |>
     orderby(desc("# of albums"))) |> fetchall
```     

```
Name=>"Iron Maiden", # of albums=>21
Name=>"Led Zeppelin", # of albums=>14
Name=>"Deep Purple", # of albums=>11
Name=>"Metallica", # of albums=>10
Name=>"U2", # of albums=>10
Name=>"Ozzy Osbourne", # of albums=>6
Name=>"Pearl Jam", # of albums=>5
Name=>"Various Artists", # of albums=>4
Name=>"Faith No More", # of albums=>4
Name=>"Foo Fighters", # of albums=>4
```
