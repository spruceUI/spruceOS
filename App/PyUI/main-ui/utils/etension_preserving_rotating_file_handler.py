import os
from logging.handlers import RotatingFileHandler

class ExtensionPreservingRotatingFileHandler(RotatingFileHandler):
    def doRollover(self):
        if self.stream:
            self.stream.close()
            self.stream = None

        base, ext = os.path.splitext(self.baseFilename)
        # base = ".../pyui"
        # ext  = ".log"

        if self.backupCount > 0:
            # Shift older logs up
            for i in range(self.backupCount - 1, 0, -1):
                sfn = "%s.%d%s" % (base, i, ext)
                dfn = "%s.%d%s" % (base, i + 1, ext)
                if os.path.exists(sfn):
                    if os.path.exists(dfn):
                        os.remove(dfn)
                    os.rename(sfn, dfn)

            # Move current log to .1.log
            dfn = "%s.1%s" % (base, ext)
            if os.path.exists(dfn):
                os.remove(dfn)
            if os.path.exists(self.baseFilename):
                os.rename(self.baseFilename, dfn)

        if not self.delay:
            self.stream = self._open()
