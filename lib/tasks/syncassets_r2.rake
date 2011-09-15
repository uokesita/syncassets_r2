require 'fog'
require 'syncassets_r2'

namespace :syncassets do

  desc "This rake task will update (delete and copy) all the files under the public directory to S3, by default is the public directory but you can pass as argument the path to the folder inside the public directory" 
  task :sync_s3_public_assets, :directory do |t, args|
    puts "#########################################################"
    puts "##          Syncing folders and files with S3          ##"
    puts "#########################################################"

    @fog = Fog::Storage.new( :provider              => 'AWS', 
                             :aws_access_key_id     => Credentials.key, 
                             :aws_secret_access_key => Credentials.secret, 
                             :persistent            => false )

    @directory = @fog.directories.create( :key => Credentials.bucket )

    @files_for_invalidation = []
    @distribution_ids       = []
    @root_directory         = "#{args[:directory]}"

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
    
    if Credentials.distribution_ids.empty?
      distributions = @cdn.get_distribution_list()
      distributions.body["DistributionSummary"].each do |distribution|
        @distribution_ids << distribution["Id"]
      end
    else
      @distribution_ids = Credentials.distribution_ids
    end
  end

  def upload_directory(asset = @root_directory || '/')
    
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

    if @root_directory.blank?
      file_name   = asset == "/" ? file : "#{asset}/#{file}".sub('/','')
    else
      file_name   = asset == "/" ? file : "#{asset}/#{file}"
    end

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
    if @root_directory.blank?
      path_to_file = asset == "/" ? "#{asset}#{file}" : "#{asset}/#{file}"
    else
      path_to_file = asset == "/" ? "/#{asset}#{file}" : "/#{asset}/#{file}"
    end
    @files_for_invalidation << path_to_file
    puts "Queued for invalidation: #{path_to_file}"
    if @files_for_invalidation.size == 200
      invalidate_files
    end
  end

  def invalidate_files
    unless @files_for_invalidation.size < 1
      get_cdn_connection
      @distribution_ids.each do |id|
        puts "Invalidating files of distribution #{id}"
        @cdn.post_invalidation(id, @files_for_invalidation, caller_reference = Time.now.to_i.to_s)
        puts "Invalidation list queued"
      end
      @files_for_invalidation.clear
    end
  end

end
