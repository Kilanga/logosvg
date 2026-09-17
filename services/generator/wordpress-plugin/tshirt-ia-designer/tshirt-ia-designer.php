<?php
/**
 * Plugin Name:       T-shirt IA Designer
 * Description:       Création de designs par IA, vectorisés automatiquement pour l'impression textile. Shortcode : [tshirt_ia_designer]
 * Version:           0.1.0
 * Requires at least: 6.3
 * Requires PHP:      7.4
 * Text Domain:       tshirt-ia
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

define( 'TSIA_VERSION', '0.1.0' );
define( 'TSIA_PATH', plugin_dir_path( __FILE__ ) );
define( 'TSIA_URL', plugin_dir_url( __FILE__ ) );

require_once TSIA_PATH . 'includes/class-tsia-settings.php';
require_once TSIA_PATH . 'includes/class-tsia-client.php';
require_once TSIA_PATH . 'includes/class-tsia-ajax.php';
require_once TSIA_PATH . 'includes/class-tsia-shortcode.php';

TSIA_Settings::init();
TSIA_Ajax::init();
TSIA_Shortcode::init();
