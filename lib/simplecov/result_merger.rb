require 'yaml'
#
# Singleton that is responsible for caching, loading and merging
# SimpleCov::Results into a single result for coverage analysis based
# upon multiple test suites.
#
module SimpleCov::ResultMerger
  class << self
    # The path to the resultset.yml cache file
    def resultset_path
      File.join(SimpleCov.coverage_path, 'resultset.yml')
    end

    def resultset_lock(&block)
      ntries = 0
      done = false
      lock_path = resultset_path+".lck"
      while ntries < 5 do
        begin
          flags = File::CREAT|File::EXCL|File::RDWR
          File.open(lock_path, flags, 0600) do |lock|
            begin
              done = block.call
            ensure
              File.unlink(lock_path)
            end
          end
        rescue Exception => e
        end
        if done then
	  break
        end
        Kernel.sleep(1)
        ntries += 1
      end
    end

    def resultset_read
      resultset = nil
      resultset_lock do
        resultset = File.read(resultset_path)
	true
      end
      return resultset
    end

    def resultset_append(&block)
      resultset_lock do
        File.open(resultset_path, "w+") do |f|
          block.call(f)
        end
	true
      end
    end
    
    # Loads the cached resultset from YAML and returns it as a Hash
    def resultset
      return {} unless File.exist?(resultset_path)
      YAML.load(resultset_read) || {}
    end
    
    # Gets the resultset hash and re-creates all included instances
    # of SimpleCov::Result from that.
    # All results that are above the SimpleCov.merge_timeout will be
    # dropped. Returns an array of SimpleCov::Result items.
    def results
      results = []
      resultset.each do |command_name, data| 
        result = SimpleCov::Result.from_hash(command_name => data)
        # Only add result if the timeout is above the configured threshold
        if (Time.now - result.created_at) < SimpleCov.merge_timeout
          results << result
        end
      end
      results
    end
    
    #
    # Gets all SimpleCov::Results from cache, merges them and produces a new
    # SimpleCov::Result with merged coverage data and the command_name 
    # for the result consisting of a join on all source result's names
    #
    def merged_result
      merged = {}
      results.each do |result|
        merged = result.original_result.merge_resultset(merged)
      end
      result = SimpleCov::Result.new(merged)
      # Specify the command name
      result.command_name = results.map(&:command_name).join(", ")
      result
    end
    
    # Saves the given SimpleCov::Result in the resultset cache
    def store_result(result)
      new_set = resultset
      command_name, data = result.to_hash.first
      new_set[command_name] = data
      resultset_append do |f|
        f.puts new_set.to_yaml
      end
      true
    end
  end
end
