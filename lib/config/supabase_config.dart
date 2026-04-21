// lib/config/supabase_config.dart
// ── Configuración Supabase — Inventario CENAM ─────────────────
// Demo: Supabase cloud (us-west-2)
// Producción: cambiar url y anonKey al servidor interno CENAM

class SupabaseConfig {
  static const String url = 'https://msptbmtvfsfsrqyixeia.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
      '.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1zcHRibXR2ZnNmc3JxeWl4ZWlhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3OTc1ODgsImV4cCI6MjA5MjM3MzU4OH0'
      '.DgyYPAxxapP1_pgJYUr-sWJPdzCGdiT6zpQjIzaeM4s';

  // Sync cada 30 segundos
  static const int syncIntervalSeg = 30;
}
