node[:deploy].each do |application, deploy|
  if deploy[:application_type] != 'other' || deploy["environment_variables"]["APP_TYPE"] != 'docker'
    Chef::Log.debug("Skipping deploy::docker application #{application} as it is not deployed to this layer")
    next
  end

  deploy["containers"].each do |c|
    c.each do |app_name, app_config|
      Chef::Log.debug("Evaluating #{app_name}...")
      e = EnvHelper.new app_name, app_config, deploy, node
      next if e.manual?

      image = app_config["image"]
      containers = app_config["containers"] || 1

      environment = e.merged_environment

      Chef::Log.debug("Deploying '#{application}/#{app_name}', from '#{image}'")

      execute "pulling #{image}" do
        Chef::Log.info("Pulling '#{image}'...")
        command "docker pull #{image}:latest"
      end

      containers.times do |i|
        ruby_block "waiting" do
          block do
            sleep(app_config["startup_time"].to_i) if app_config["startup_time"] && i > 0
          end
        end

        execute "kill running #{app_name}#{i} container" do
          Chef::Log.info("Killing running #{application}/#{app_name}#{i} container...")
          command "docker kill #{app_name}#{i}"
          only_if "docker ps -f status=running | grep ' #{app_name}#{i} '"
        end

        execute "remove stopped #{app_name}#{i} container" do
          Chef::Log.info("Removing the #{application}/#{app_name}#{i} container...")
          command "docker rm  #{app_name}#{i}"
          only_if "docker ps -a | grep ' #{app_name}#{i} '"
        end

        execute "migrate #{app_name}#{i} container" do
          Chef::Log.info("Migrating #{app_name}#{i}...")
          command "docker run --rm #{e.env_string(environment)} #{e.links} #{e.volumes} #{e.volumes_from} #{image} #{app_config["migration"]}"
          only_if { e.migrate? && i == 0}
        end

        execute "launch #{app_name}#{i} container" do
          environment["RELEASE_TAG"] = `docker history -q #{image} | head -1`.strip
          Chef::Log.info("Launching #{image}...")
          command "docker run -d -h #{e.hostname i} --name #{app_name}#{i} #{e.ports} #{e.env_string(environment)} #{e.links} #{e.volumes} #{e.volumes_from} #{e.entrypoint} #{image} #{e.cmd i}"
          only_if { e.auto? }
          notifies :run, "execute[get deployments info #{app_name}#{i} container]", :immediately
        end

        ruby_block "get deployments info #{app_name}#{i} container" do
          Chef::Log.info("Get deployments info #{app_name}#{i} container...")
          block do
            default[:deploy][application][:containers][app_name][:deployments] = {
              :release_tag  => environment["RELEASE_TAG"],
              :git_revision => `docker run #{image} -c 'echo $GIT_REVISION'`
            }
          end
          action :nothing
        end

        cron "#{app_name}#{i} cron" do
          action :create
          minute e.cron["minute"]
          hour e.cron["hour"]
          weekday e.cron["weekday"]
          command "docker run --rm --name #{app_name}#{i} #{e.env_string(environment)} #{e.links} #{e.volumes} #{e.volumes_from} #{e.entrypoint} #{image} #{app_config["command"]}"
          only_if { e.cron? }
        end

      end
    end
  end
end
