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
> records[1][:age] |> get
45.1
```

More advanced querying
===========

SQLAlchemy ships the [Chinook](https://chinookdatabase.codeplex.com/wikipage?title=Chinook_Schema&referringTitle=Home) sqlite database as learning tool and a conveience function ``loadchinook` to open a sqlite connection to it.

In this example, we'll see which artist has the most albums in the Chinook db.

```julia
> using SQLAlchemy
> db, tables = loadchinook()
# Let's look at part of the Album and Artist tables
> artists, albums = tables["Artist"], tables["Album"]
> db(select([artists])) |> fetchall
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
> db(select([albums])) |> fetchall
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
> db(select([artists[:Name],
             func("count", albums[:Title]) |> label("# of albums")]) |>
     selectfrom(join(artists, albums)) |>
     groupby(albums[:ArtistId]) |>
     orderby(desc("# of albums"))) |> fetchall
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
