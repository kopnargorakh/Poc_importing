def doGet(request, session):
    try:
        import json
        
        tags_file = "C:/Program Files/Inductive Automation/Ignition/data/config/resources/core/ignition/tag-definition/default/tags.json"
        tags_json = system.file.readFileAsString(tags_file)
        tags_data = json.loads(tags_json)
        
        if isinstance(tags_data, dict) and "tags" in tags_data:
            tags_to_configure = tags_data["tags"]
        else:
            tags_to_configure = tags_data
        
       
        existing = system.tag.browseTags(parentPath="")
        for tag in existing:
            tag_name = str(tag.path).strip("/")
            system.tag.deleteTags(["[default]/" + tag_name])
        
     
        for tag in tags_to_configure:
            system.tag.configure("[default]", json.dumps(tag), 'o')
        
        return {"json": {
            "status": "success",
            "message": "Tags deployed",
            "count": len(tags_to_configure)
        }}
    except Exception as e:
        return {"json": {"status": "error", "message": str(e)}}
