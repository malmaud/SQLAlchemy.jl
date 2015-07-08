using BinDeps
using Compat

@BinDeps.setup

sqlite3 = library_dependency("sqlite3",
    aliases=["sqlite3", "libsqlite3", "sqlite3-64", "libsqlite3-0"])

@osx_only begin
  using Homebrew
  provides(Homebrew.HB, @compat Dict("sqlite3"=>sqlite3))
end

@unix_only begin
  provides(AptGet, @compat Dict("sqlite3"=>sqlite3))
  try
    py_info = readall(`pip show sqlalchemy`)
    m = match(r"Version: (.*)", py_info)
    version = @compat VersionNumber(m.captures[1])
    if version < v"1"
      info("Attempting to install sqlalchemy python package via pip")
      try
        run(`pip install --upgrade sqlalchemy`)
      catch
        run(`sudo pip install --upgrade sqlalchemy`)
      end
    end
  catch err
    warn("Couldn't automatically install sqlalchemy. Run 'pip install sqlalchemy' manually.\nError was $err")
  end
end

@windows_only begin
    using WinRPM
    provides(WinRPM.RPM, @compat Dict("libsqlite3-0"=>sqlite3))
end

@BinDeps.install
