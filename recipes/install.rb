# Warning: It assumes you're using Amazon Linux
# Does not support any other platform but extending it
# is trivial.

docker_install do
end

service "docker" do
  action :start
end
