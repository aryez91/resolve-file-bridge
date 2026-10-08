-- Smallest possible command: who and where am I?
result = {
  bridge = bridge.version,
  comp = comp and comp:GetAttrs().COMPS_Name,
  page = bridge.resolve() and bridge.resolve():GetCurrentPage(),
  frame = comp and comp.CurrentTime,
}
