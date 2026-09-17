<?php
if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/**
 * Page Réglages > T-shirt IA.
 *
 * Les secrets peuvent aussi être définis dans wp-config.php pour ne pas les stocker en base :
 *   define( 'TSIA_API_KEY', '...' );
 *   define( 'TSIA_TURNSTILE_SECRET', '...' );
 */
class TSIA_Settings {
	const OPTION = 'tsia_settings';

	const DEFAULTS = array(
		'service_url'        => '',
		'api_key'            => '',
		'turnstile_site_key' => '',
		'turnstile_secret'   => '',
		'daily_quota'        => 5,
	);

	const CONSTANTS = array(
		'api_key'          => 'TSIA_API_KEY',
		'turnstile_secret' => 'TSIA_TURNSTILE_SECRET',
	);

	public static function init() {
		add_action( 'admin_menu', array( __CLASS__, 'menu' ) );
		add_action( 'admin_init', array( __CLASS__, 'register' ) );
	}

	public static function get( $key ) {
		if ( isset( self::CONSTANTS[ $key ] ) && defined( self::CONSTANTS[ $key ] ) ) {
			return (string) constant( self::CONSTANTS[ $key ] );
		}
		$options = wp_parse_args( (array) get_option( self::OPTION, array() ), self::DEFAULTS );
		return $options[ $key ];
	}

	public static function menu() {
		add_options_page( 'T-shirt IA', 'T-shirt IA', 'manage_options', 'tsia-settings', array( __CLASS__, 'render' ) );
	}

	public static function register() {
		register_setting(
			'tsia_settings_group',
			self::OPTION,
			array( 'sanitize_callback' => array( __CLASS__, 'sanitize' ) )
		);
	}

	public static function sanitize( $input ) {
		$current = wp_parse_args( (array) get_option( self::OPTION, array() ), self::DEFAULTS );
		$input   = (array) $input;
		$clean   = array();

		$clean['service_url']        = esc_url_raw( trim( $input['service_url'] ?? '' ), array( 'https', 'http' ) );
		$clean['turnstile_site_key'] = sanitize_text_field( $input['turnstile_site_key'] ?? '' );
		$clean['daily_quota']        = min( 100, absint( $input['daily_quota'] ?? 5 ) );

		// Un champ secret laissé vide conserve la valeur enregistrée.
		foreach ( array( 'api_key', 'turnstile_secret' ) as $secret ) {
			$value            = trim( sanitize_text_field( $input[ $secret ] ?? '' ) );
			$clean[ $secret ] = '' === $value ? $current[ $secret ] : $value;
		}
		return $clean;
	}

	public static function render() {
		if ( ! current_user_can( 'manage_options' ) ) {
			return;
		}
		$fields = array(
			'service_url'        => array( 'Adresse du service', 'url', 'URL du tunnel, par exemple https://xxxx.trycloudflare.com' ),
			'api_key'            => array( 'Clé API du service', 'password', 'La valeur API_KEY du fichier .env. Laisser vide pour conserver la clé actuelle.' ),
			'turnstile_site_key' => array( 'Turnstile : clé de site', 'text', 'Tableau de bord Cloudflare > Turnstile. Laisser vide pour désactiver la vérification.' ),
			'turnstile_secret'   => array( 'Turnstile : clé secrète', 'password', 'Laisser vide pour conserver la clé actuelle.' ),
			'daily_quota'        => array( 'Générations par client et par jour', 'number', '0 = illimité (déconseillé).' ),
		);
		?>
		<div class="wrap">
			<h1>T-shirt IA</h1>
			<p>Ajoutez le shortcode <code>[tshirt_ia_designer]</code> sur la page de création de design.</p>
			<form method="post" action="options.php">
				<?php settings_fields( 'tsia_settings_group' ); ?>
				<table class="form-table" role="presentation">
					<?php
					foreach ( $fields as $key => $field ) :
						list( $label, $type, $help ) = $field;
						$locked                      = isset( self::CONSTANTS[ $key ] ) && defined( self::CONSTANTS[ $key ] );
						$is_secret                   = 'password' === $type;
						$value                       = $is_secret ? '' : self::get( $key );
						$has_secret                  = $is_secret && '' !== self::get( $key );
						?>
						<tr>
							<th scope="row"><label for="tsia-<?php echo esc_attr( $key ); ?>"><?php echo esc_html( $label ); ?></label></th>
							<td>
								<?php if ( $locked ) : ?>
									<p>Défini dans wp-config.php.</p>
								<?php else : ?>
									<input
										id="tsia-<?php echo esc_attr( $key ); ?>"
										class="regular-text"
										type="<?php echo esc_attr( $type ); ?>"
										name="<?php echo esc_attr( self::OPTION . '[' . $key . ']' ); ?>"
										value="<?php echo esc_attr( $value ); ?>"
										autocomplete="off"
										<?php echo 'number' === $type ? 'min="0" max="100"' : ''; ?>
										<?php echo $has_secret ? 'placeholder="Enregistrée"' : ''; ?>
									/>
									<p class="description"><?php echo esc_html( $help ); ?></p>
								<?php endif; ?>
							</td>
						</tr>
					<?php endforeach; ?>
				</table>
				<?php submit_button( 'Enregistrer les réglages' ); ?>
			</form>
		</div>
		<?php
	}
}
