.section __TEXT,__rvmanifest,regular,no_dead_strip
.p2align 4
.globl _raven_manifest_start
_raven_manifest_start:
.incbin "Resources/RavenModel.mlpackage/Manifest.json"
.globl _raven_manifest_end
_raven_manifest_end:

.section __TEXT,__rvmodel,regular,no_dead_strip
.p2align 4
.globl _raven_model_start
_raven_model_start:
.incbin "Resources/RavenModel.mlpackage/Data/com.apple.CoreML/model.mlmodel"
.globl _raven_model_end
_raven_model_end:

.section __TEXT,__rvweights,regular,no_dead_strip
.p2align 4
.globl _raven_weights_start
_raven_weights_start:
.incbin "Resources/RavenModel.mlpackage/Data/com.apple.CoreML/weights/weight.bin"
.globl _raven_weights_end
_raven_weights_end:
