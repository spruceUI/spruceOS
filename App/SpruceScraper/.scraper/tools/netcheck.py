"""Can this device reach ScreenScraper over HTTPS the way Skyscraper will?

Skyscraper reports a refused or unverifiable connection as every game "not found", so the app asks
first. Prints one line that starts with the answer:

    ok           reachable (or the check could not tell: Skyscraper decides)
    offline      no route, no DNS or no connection
    clock        the server's certificate is not valid at this device's date
    certificate  the certificate does not verify against the CA file

    python3 netcheck.py [CA_FILE [HOST[:PORT]]]

Without a CA file only the connection is tested: Skyscraper then uses the firmware's certificates,
which this python may not find in the same place. HOST is for tests/test_netcheck.py.
"""
import socket
import sys

HOST = "www.screenscraper.fr"
# X509_V_ERR_CERT_NOT_YET_VALID, X509_V_ERR_CERT_HAS_EXPIRED
CLOCK_CODES = (9, 10)


def check(cafile="", target=HOST):
    host, _, port = target.partition(":")
    try:
        sock = socket.create_connection((host, int(port or 443)), 8)
    except OSError as exc:
        return "offline: %s" % exc
    with sock:
        if not cafile:
            return "ok (connection only: no CA file)"
        try:
            import ssl
        except ImportError:
            return "ok (connection only: this python has no ssl)"
        try:
            context = ssl.create_default_context(cafile=cafile)
            with context.wrap_socket(sock, server_hostname=host):
                return "ok"
        except ssl.SSLCertVerificationError as exc:
            word = "clock" if exc.verify_code in CLOCK_CODES else "certificate"
            return "%s: %s" % (word, exc.verify_message)
        except (ssl.SSLError, OSError) as exc:
            return "ok (not verified: %s)" % exc


if __name__ == "__main__":
    print(check(*sys.argv[1:3]))
