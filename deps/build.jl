try
  run(`pip install --upgrade sqlalchemy`)
catch err
  warn("Couldn't automatically install sqlalchemy: $err")
end
