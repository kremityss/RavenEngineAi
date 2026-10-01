def run_preflight(cfg):
    from ascript.ios import screen
    from ascript.ios.system import R
    report = {"screen": None, "orientation": None, "capture": False, "model_paths": {}}
    try:
        report["screen"] = list(screen.size())
        report["orientation"] = str(screen.ori())
        frame = screen.capture(format=screen.FORMAT_CV_MAT)
        report["capture"] = frame is not None
    except Exception as e:
        report["capture_error"] = str(e)
    for key in ("model_param","model_bin","model_yaml"):
        try:
            report["model_paths"][key] = R.res(cfg[key])
        except Exception as e:
            report["model_paths"][key] = str(e)
    return report
