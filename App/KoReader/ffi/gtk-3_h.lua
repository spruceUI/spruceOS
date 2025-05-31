local ffi = require("ffi")

ffi.cdef[[
typedef int gint;
typedef char gchar;
typedef int gboolean;
typedef struct _GtkDialog GtkDialog;
typedef struct _GtkWidget GtkWidget;
typedef struct _GtkWindow GtkWindow;
typedef struct _GtkFileChooser GtkFileChooser;
typedef enum {
  GTK_FILE_CHOOSER_ACTION_OPEN = 0,
  GTK_FILE_CHOOSER_ACTION_SAVE = 1,
  GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER = 2,
  GTK_FILE_CHOOSER_ACTION_CREATE_FOLDER = 3,
} GtkFileChooserAction;
typedef enum {
  GTK_RESPONSE_NONE = -1,
  GTK_RESPONSE_REJECT = -2,
  GTK_RESPONSE_ACCEPT = -3,
  GTK_RESPONSE_DELETE_EVENT = -4,
  GTK_RESPONSE_OK = -5,
  GTK_RESPONSE_CANCEL = -6,
  GTK_RESPONSE_CLOSE = -7,
  GTK_RESPONSE_YES = -8,
  GTK_RESPONSE_NO = -9,
  GTK_RESPONSE_APPLY = -10,
  GTK_RESPONSE_HELP = -11,
} GtkResponseType;
void gtk_init(int *, char ***);
gboolean gtk_events_pending(void);
gboolean gtk_main_iteration(void);
GtkWidget *gtk_file_chooser_dialog_new(const gchar *, GtkWindow *, GtkFileChooserAction, const gchar *, ...);
gint gtk_dialog_run(GtkDialog *);
void gtk_widget_destroy(GtkWidget *);
gchar *gtk_file_chooser_get_filename(GtkFileChooser *);
]]
