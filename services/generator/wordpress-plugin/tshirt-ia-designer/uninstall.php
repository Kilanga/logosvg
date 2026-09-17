<?php
if ( ! defined( 'WP_UNINSTALL_PLUGIN' ) ) {
	exit;
}
delete_option( 'tsia_settings' );
delete_metadata( 'user', 0, 'tsia_usage', '', true );
delete_metadata( 'user', 0, 'tsia_jobs', '', true );
