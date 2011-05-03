require 'fog'
namespace :syncassets do

  desc "Synchronize public folder with s3" 
  task :sync_s3_public_assets do
    puts "#########################################################"
    puts "##      This rake task will update (delete and copy)     "
    puts "##      all the files under /public on s3, be patient    "
    puts "#########################################################"

    @settings = YAML.load_file(File.join(Rails.root, 'config', 's3.yml'))
    @fog = Fog::Storage.new( :provider              => 'AWS', 
                             :aws_access_key_id     => @settings['aws_access_key'], 
                             :aws_secret_access_key => @settings['aws_secret_access_key'], 
                             :persistent            => false )
    @directory = @fog.directories.create( :key => @settings['aws_bucket_name'] )

    upload_directory
  end

  def upload_directory(asset='/')
    Dir.entries(File.join(Rails.root, 'public', asset)).each do |file|
      next if file =~ /\A\./
      
      if File.directory? File.join(Rails.root, 'public', asset, file)
        upload_directory File.join(asset, file)
      else
        upload_file(asset, file)
      end
    end
  end

  def upload_file asset, file
    file_name   = asset == "/" ? file : "#{asset}/#{file}".sub('/','')
    remote_file = get_remote_file(file_name)

    if check_timestamps(file_name, remote_file)
      destroy_file(remote_file)
      file_u = @directory.files.create(:key => "#{file_name}", :body => open(File.join(Rails.root, 'public', asset, file )), :public => true )
      puts "copied #{file_name}"
    end
  end

  def get_remote_file file_name
    remote_file = @directory.files.get(file_name)
  end
  
  def check_timestamps local_file, remote_file
    puts "verifing file: #{local_file}"
    local  = File.mtime(File.join(Rails.root, 'public', local_file))
    unless remote_file.nil?
      return local > remote_file.last_modified
    end
    true 
  end

  def destroy_file remote_file
    unless remote_file.nil?
      remote_file.destroy
      puts "delete on s3 #{remote_file.key}"
    end
  end

end
