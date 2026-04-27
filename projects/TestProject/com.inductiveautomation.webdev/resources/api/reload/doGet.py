def doGet(request, session):
    try:
        system.project.requestScan()
        return {'json': {'status': 'ok', 'message': 'Scan triggered'}}
    except Exception as e:
        return {'json': {'status': 'error', 'message': str(e)}}
