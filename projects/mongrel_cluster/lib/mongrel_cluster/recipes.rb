
if respond_to?(:namespace)
  require 'mongrel_cluster/recipes_2' # Cap 2
else  
  require 'mongrel_cluster/recipes_1' # Cap 1
end
