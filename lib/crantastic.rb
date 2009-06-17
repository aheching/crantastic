module Crantastic

  class UpdatePackages
    # To limit the number of updates per hour to avoid long-running processes,
    # set =max= to a positive digit.
    def start(max=-1)
      Log.log!("Starting cron task: UpdatePackages")
      known_versions = Package.all
      latest_versions = CRAN::Packages.new("http://cran.r-project.org/src/contrib/PACKAGES.gz").sort

      i = 0
      latest_versions.each do |new|
        break if i == max
        cur = known_versions.find { |pkg| pkg.name == new.name }
        if cur
          if !cur.latest || (cur.latest.version != new.version.to_s)
            Log.log!("Updating package: #{new}")
            add_version_to_db(new)
            i += 1
          end
        else
          Log.log!("New package: #{new}")
          Package.create!(:name => new.name) # Start by creating the package entry
          add_version_to_db(new)
          i += 1
        end
      end
      Log.log!("Cron task finished.")
      return true
    end

    def add_version_to_db(pkg)
      gz = Zlib::GzipReader.new(open("http://cran.r-project.org/src/contrib/#{pkg.name}_#{pkg.version}.tar.gz"))
      Archive::Tar::Minitar.unpack(gz, File.join(RAILS_ROOT, "/tmp"))
      pkgdir = File.join(RAILS_ROOT, "/tmp/#{pkg.name}/")

      description = Dcf.parse(File.read(pkgdir + "DESCRIPTION"))
      throw Exception.new("Couldn't parse DESCRIPTION for #{pkg.name}. " +
                          "Look at http://cran.r-project.org/web/packages/#{pkg.name}/DESCRIPTION " +
                          "for clues.") if description.nil?
      data = description.first
      data = data.downcase_keys.symbolize_keys

      fields = [:title, :license, :description, :author,
                :maintainer,:date, :url, :depends, :suggests]
      data.delete_if { |k,v| !fields.include?(k) } # Remove unwanted fields

      data.merge!(read_from_files(pkgdir, %w(README NEWS)))
      # No standard for what the changelog file should be called so we try a bunch
      data[:changelog] = read_from_files(pkgdir, %w(CHANGELOG ChangeLog Changes)).values.first

      data.merge!(pkg.to_hash)

      # We must convert every value to UTF-8
      data = data.inject({}) { |b, (k,v)| b[k] = v.latin1_to_utf8 if v; b }

      begin
        data[:date] = Date.parse(data[:date])
      rescue
        data[:date] = nil
      end

      # Find or create maintainer
      data[:maintainer] = Author.new_from_string(data[:maintainer])

      data[:package] = Package.find_by_name(pkg.name)
      Version.create!(data)
      FileUtils.rm_rf(pkgdir)
    rescue OpenURI::HTTPError, SocketError, URI::InvalidURIError
      Log.log! "Problem downloading #{pkg}, skipping to next pkg"
    end

    def read_from_files(pkgdir, files)
      data = {}
      files.each do |f|
        if File.exists?(pkgdir + f)
          data[f.downcase.to_sym] = File.read(pkgdir + f)
        else
          if File.exists?(pkgdir + "inst/" + f)
            data[f.downcase.to_sym] = File.read(pkgdir + "inst/" + f)
          end
        end
      end
      data
    end
  end

  class UpdateTaskViews
    def start
      views = CRAN::TaskViews.new(open("http://cran.r-project.org/web/views/index.html").read)
      views.each do |v|
        # TODO: check view version, simply skip if it hasnt been updated.
        # If it has changed, we have to look through all previously tagged
        # packages for this view, to check if they have been removed from te view.
        view = CRAN::TaskView.new(open("http://cran.r-project.org/web/views/#{v}.ctv").read)
        tag = Tag.find(:first, :conditions => { :name => view.name,
                                                :task_view => true })
        view.packagelist.each do |pkg|
          # 146 = crantastic user
          conds = {
            :package_id => Package.find_by_name(pkg).id,
            :user_id => 146,
            :tag_id => tag.id
          }
          Tagging.create!(conds) unless Tagging.find(:first, :conditions => conds)
        end
      end
    end
  end

end