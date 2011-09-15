class Auth
  def self.root
    rails_root = (Rails.version < "2.1.2") ? RAILS_ROOT : Rails.root
    YAML::load(IO.read(File.join(rails_root, 'config', 'aws.yml')))
  end
  def self.env
    rails_env = (Rails.version < "2.1.2") ? RAILS_ENV   : Rails.env
  end
end


class Credentials
  def initialize
# TRIED USING THE INITIALIZE FOR THOSE YAML LOADING DOWN THERE
# BUT IT WAS GIVING ME CRAP AND HAD TO DUPLICATE THE LINE
# MY GUEST IS THAT IT IS B/C THEY ARE CLASS METHODS
# TODO: RESEARCH HOW TO REFACTOR OUT
  end

  begin
    def self.key
      Auth.root[Auth.env]['access_key_id']
    end
    def self.secret
      Auth.root[Auth.env]['secret_access_key']
    end
    def self.bucket
      Auth.root[Auth.env]['bucket']
    end
    def self.distribution_ids
      unless Auth.root[Auth.env]['distribution_ids'].nil?
        return Auth.root[Auth.env]['distribution_ids'].gsub(' ','').split(',')
      end
      []
    end
  rescue
    puts"syncassets_r3 : AWS Access Key Id needs a subscription for the service."
  end
end

