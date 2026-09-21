package com.polartico.clock_in

import androidx.core.content.FileProvider

// Own subclass so this provider never collides with FileProviders declared by plugins
class UpdateFileProvider : FileProvider()
