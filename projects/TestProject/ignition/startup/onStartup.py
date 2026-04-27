def onStartup():
	import json
	tags_file = "C:/Program Files/Inductive Automation/Ignition/data/config/resources/core/ignition/tag-definition/default/tags.json"
	
	try:
	    tags_json = system.file.readFileAsString(tags_file)
	    tags_data = json.loads(tags_json)
	    
	    if isinstance(tags_data, dict) and "tags" in tags_data:
	        tags_to_configure = tags_data["tags"]
	    else:
	        tags_to_configure = tags_data
	    
	    # Saare existing delete karo
	    existing = system.tag.browseTags(parentPath="")
	    for tag in existing:
	        tag_name = str(tag.path).strip("/")
	        system.tag.deleteTags(["[default]/" + tag_name])
	    
	    # Fresh create karo
	    for tag in tags_to_configure:
	        system.tag.configure("[default]", json.dumps(tag), 'o')
	        
	except Exception as e:
	    pass
	
