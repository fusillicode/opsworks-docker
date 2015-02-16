define :docker_install do
  platform = params[:platform] or 'amazon'
  config = params[:config] or {}
  case platform
  when 'amazon'
    package 'docker' do
      action :install
    end
  when 'ubuntu'
    include_recipe 'apt::repository'
    package 'apt-transport-https' do
      action :install
    end
    apt_repository 'docker' do
      uri config[:uri]
      components config[:components]
      keyserver config[:keyserver]
      key config[:key]
      deb_src config[:deb_src]
    end
    package 'lxc-docker' do
      action :install
    end
  end
end
