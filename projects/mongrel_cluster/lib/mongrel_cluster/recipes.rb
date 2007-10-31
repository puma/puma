
if respond_to?(:namespace)
  # Cap 2
  load 'mongrel_cluster/recipes_2' 
else
  # Cap 2
  load 'mongrel_cluster/recipes_1'
end
