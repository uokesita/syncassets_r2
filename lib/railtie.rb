require 'syncassets_r2'
require 'rails'

class Railtie < Rails::Railtie
  rake_tasks do
    load "tasks/syncassets_r2.rake"
  end
end

