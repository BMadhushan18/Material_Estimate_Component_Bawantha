import sys
try:
    import main
    print('Imported main ok')
except Exception as e:
    print('Import error:', e)
    raise
