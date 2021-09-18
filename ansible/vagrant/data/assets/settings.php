<?php

/**
 * @file
 * Drupal site-specific configuration file.
 */

$databases = array();
$update_free_access = FALSE;
$drupal_hash_salt = 'zVDkoMaGUHzwWwbH9FmtRuhnIoiy21xPM5mxVJT6igE';

$conf['404_fast_paths_exclude'] = '/\/(?:styles)|(?:system\/files)\//';
$conf['404_fast_paths'] = '/\.(?:txt|png|gif|jpe?g|css|js|ico|swf|flv|cgi|bat|pl|dll|exe|asp)$/i';
$conf['404_fast_html'] = '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML+RDFa 1.0//EN" "http://www.w3.org/MarkUp/DTD/xhtml-rdfa-1.dtd"><html xmlns="http://www.w3.org/1999/xhtml"><head><title>404 Not Found</title></head><body><h1>Not Found</h1><p>The requested URL "@path" was not found on this server.</p></body></html>';

$relationships = getenv("PLATFORM_RELATIONSHIPS");
if ($relationships) {
  $relationships = json_decode(base64_decode($relationships), TRUE);

  if (empty($databases['default']['default']) && !empty($relationships['database'])) {
    foreach ($relationships['database'] as $endpoint) {
      $database = array(
        'driver' => $endpoint['scheme'],
        'database' => $endpoint['path'],
        'username' => $endpoint['username'],
        'password' => $endpoint['password'],
        'host' => $endpoint['host'],
        'port' => $endpoint['port'],
      );

      if (!empty($endpoint['query']['compression'])) {
        $database['pdo'][PDO::MYSQL_ATTR_COMPRESS] = TRUE;
      }

      if (!empty($endpoint['query']['is_master'])) {
        $databases['default']['default'] = $database;
      }
      else {
        $databases['default']['slave'][] = $database;
      }
    }
  }

  if (!empty($relationships['solr'])) {
    foreach ($relationships['solr'] as $endpoint) {
      $conf['search_api_solr_overrides'] = array(
        'solr_server' => array(
          'name' => t('Solr Server (Overridden)'),
          'options' => array(
            'host' => $endpoint['host'],
            'port' => $endpoint['port'],
            'path' => '/solr',
          ),
        ),
      );
    }
  }
}

// Configure private and temporary file paths.
if (isset($_ENV['PLATFORM_APP_DIR'])) {
  if (!isset($conf['file_private_path'])) {
    $conf['file_private_path'] = $_ENV['PLATFORM_APP_DIR'] . '/private';
  }
  if (!isset($conf['file_temporary_path'])) {
    $conf['file_temporary_path'] = $_ENV['PLATFORM_APP_DIR'] . '/tmp';
  }
}

// Import variables prefixed with 'drupal:' into $conf.
if (isset($_ENV['PLATFORM_VARIABLES'])) {
  $variables = json_decode(base64_decode($_ENV['PLATFORM_VARIABLES']), TRUE);

  $prefix_len = strlen('drupal:');
  $drupal_globals = array(
    'cookie_domain',
    'installed_profile',
    'drupal_hash_salt',
    'base_url',
  );

  foreach ($variables as $name => $value) {
    if (substr($name, 0, $prefix_len) == 'drupal:') {
      $name = substr($name, $prefix_len);
      if (in_array($name, $drupal_globals)) {
        $GLOBALS[$name] = $value;
      }
      else {
        $conf[$name] = $value;
      }
    }
  }
}

// Set a default Drupal hash salt, based on a project-specific entropy value.
if (isset($_ENV['PLATFORM_PROJECT_ENTROPY']) && empty($drupal_hash_salt)) {
  $drupal_hash_salt = $_ENV['PLATFORM_PROJECT_ENTROPY'];
}

// Default PHP settings.
ini_set('session.gc_probability', 1);
ini_set('session.gc_divisor', 100);
ini_set('session.gc_maxlifetime', 3600);
ini_set('session.cookie_lifetime', 3600);
ini_set('pcre.backtrack_limit', 200000);
ini_set('pcre.recursion_limit', 200000);

// Force Drupal not to check for HTTP connectivity until we fixed the self test.
$conf['drupal_http_request_fails'] = FALSE;

$local_settings = dirname(__FILE__) . '/settings.local.php';
if (file_exists($local_settings)) {
  require $local_settings;
}

$test_settings = dirname(__FILE__) . '/settings.test.php';
if (file_exists($test_settings)) {
  require $test_settings;
}

// Force Database cache for certain tables.
$drush_command = function_exists('drush_get_command') ? drush_get_command() : FALSE;
if (!drupal_installation_attempted() && (!$drush_command || $drush_command['command'] != 'site-install')) {
  $conf['cache_class_cache_form'] = 'DrupalDatabaseCache';
  $conf['cache_class_cache_field'] = 'DrupalDatabaseCache';
  $conf['cache_class_cache_bootstrap'] = 'DrupalDatabaseCache';
}

// Set custom exception handler to add backtrace to EntityMalformedException.
include_once '../modules/features/irma_ecas/watchdog_backtrace.inc';
if (function_exists('_emnies_backtrace_exception_handler')) {
  set_exception_handler('_emnies_backtrace_exception_handler');
}