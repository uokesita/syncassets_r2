require 'fog'
require 'syncassets_r2'
namespace :syncassets do

  desc "Synchronize public folder with s3" 
  task :sync_s3_public_assets do
    puts "#########################################################"
    puts "##      This rake task will update (delete and copy)     "
    puts "##      all the files under /public on s3, be patient    "
    puts "#########################################################"

    @fog = Fog::Storage.new( :provider              => 'AWS', 
                             :aws_access_key_id     => Credentials.key, 
                             :aws_secret_access_key => Credentials.secret, 
                             :persistent            => false )

    @directory = @fog.directories.create( :key => Credentials.bucket )

    @files_for_invalidation = []
    @distribution_ids       = []

    get_distribution_ids
    upload_directory
    invalidate_files
  end

  def get_cdn_connection
    @cdn = Fog::CDN.new( :provider              => 'AWS',
                         :aws_access_key_id     => Credentials.key,
                         :aws_secret_access_key => Credentials.secret )
  end

  def get_distribution_ids
    get_cdn_connection

    distributions = @cdn.get_distribution_list()
    distributions.body["DistributionSummary"].each do |distribution|
      @distribution_ids << distribution["Id"]
    end
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
      queue_file_for_invalidation(asset, file)
      puts "Copied: #{file_name}"
    end
  end

  def get_remote_file file_name
    remote_file = @directory.files.get(file_name)
  end
  
  def check_timestamps local_file, remote_file
    puts "Verifing file: #{local_file}"
    local  = File.mtime(File.join(Rails.root, 'public', local_file))
    unless remote_file.nil?
      return local > remote_file.last_modified
    end
    true 
  end

  def destroy_file remote_file
    unless remote_file.nil?
      remote_file.destroy
      puts "Delete on s3: #{remote_file.key}"
    end
  end

  def queue_file_for_invalidation asset, file
    path_to_file = asset == "/" ? "#{asset}#{file}" : "#{asset}/#{file}"
    @files_for_invalidation << path_to_file
    puts "Queued for invalidation: #{path_to_file}"
  end

  def invalidate_files
    get_cdn_connection

    @distribution_ids.each do |id|
      puts "Invalidating files of distribution #{id}"
      @cdn.post_invalidation(id, @files_for_invalidation, caller_reference = Time.now.to_i.to_s)
      puts "Invalidation list queued"
    end
  end

end
