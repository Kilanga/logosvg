<?php
if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/**
 * Points d'entrée AJAX appelés par le navigateur : démarrer un design, suivre son avancement.
 */
class TSIA_Ajax {
	const STYLES   = array( 'logo', 'illustration', 'mascotte', 'badge' );
	const MAX_JOBS = 20;

	public static function init() {
		add_action( 'wp_ajax_tsia_start', array( __CLASS__, 'start' ) );
		add_action( 'wp_ajax_tsia_status', array( __CLASS__, 'status' ) );
		add_action( 'wp_ajax_nopriv_tsia_start', array( __CLASS__, 'require_login' ) );
		add_action( 'wp_ajax_nopriv_tsia_status', array( __CLASS__, 'require_login' ) );
	}

	public static function require_login() {
		wp_send_json_error( array( 'message' => 'Connectez-vous pour créer un design.' ), 401 );
	}

	/** Identifiant pseudonymisé transmis au microservice (pas d'ID WordPress en clair). */
	private static function user_key( $user_id ) {
		return substr( hash_hmac( 'sha256', 'tsia-' . $user_id, wp_salt( 'auth' ) ), 0, 32 );
	}

	private static function fail( WP_Error $error ) {
		$data   = $error->get_error_data();
		$status = ( is_array( $data ) && isset( $data['status'] ) ) ? (int) $data['status'] : 400;
		wp_send_json_error( array( 'message' => $error->get_error_message() ), $status );
	}

	private static function verify_turnstile() {
		$secret = (string) TSIA_Settings::get( 'turnstile_secret' );
		if ( '' === $secret ) {
			return true;
		}
		$token = isset( $_POST['cf-turnstile-response'] ) ? sanitize_text_field( wp_unslash( $_POST['cf-turnstile-response'] ) ) : '';
		if ( '' === $token ) {
			return false;
		}
		$response = wp_remote_post(
			'https://challenges.cloudflare.com/turnstile/v0/siteverify',
			array(
				'timeout' => 10,
				'body'    => array(
					'secret'   => $secret,
					'response' => $token,
					'remoteip' => isset( $_SERVER['REMOTE_ADDR'] ) ? sanitize_text_field( wp_unslash( $_SERVER['REMOTE_ADDR'] ) ) : '',
				),
			)
		);
		if ( is_wp_error( $response ) ) {
			return false;
		}
		$data = json_decode( wp_remote_retrieve_body( $response ), true );
		return is_array( $data ) && ! empty( $data['success'] );
	}

	public static function start() {
		check_ajax_referer( 'tsia_designer', 'nonce' );
		$user_id = get_current_user_id();

		// Quota journalier côté WordPress (le microservice a sa propre limite en plus).
		$quota = (int) TSIA_Settings::get( 'daily_quota' );
		$today = current_time( 'Y-m-d' );
		$usage = get_user_meta( $user_id, 'tsia_usage', true );
		if ( ! is_array( $usage ) || ( $usage['date'] ?? '' ) !== $today ) {
			$usage = array( 'date' => $today, 'count' => 0 );
		}
		if ( $quota > 0 && $usage['count'] >= $quota ) {
			wp_send_json_error(
				array( 'message' => sprintf( 'Vous avez utilisé vos %d créations du jour. Vous pourrez en lancer de nouvelles demain.', $quota ) ),
				429
			);
		}

		if ( ! self::verify_turnstile() ) {
			wp_send_json_error( array( 'message' => 'La vérification anti-robot a échoué. Rechargez la page puis relancez la création.' ), 403 );
		}

		$prompt = isset( $_POST['prompt'] ) ? sanitize_textarea_field( wp_unslash( $_POST['prompt'] ) ) : '';
		$length = function_exists( 'mb_strlen' ) ? mb_strlen( $prompt ) : strlen( $prompt );
		if ( $length < 3 || $length > 300 ) {
			wp_send_json_error( array( 'message' => 'Décrivez votre design en 3 à 300 caractères.' ), 400 );
		}

		$style = isset( $_POST['style'] ) ? sanitize_key( wp_unslash( $_POST['style'] ) ) : 'illustration';
		if ( ! in_array( $style, self::STYLES, true ) ) {
			$style = 'illustration';
		}
		$colors    = isset( $_POST['colors'] ) ? max( 1, min( 6, absint( $_POST['colors'] ) ) ) : 3;
		$remove_bg = isset( $_POST['remove_background'] ) && '1' === $_POST['remove_background'];

		$result = TSIA_Client::start_job(
			array(
				'prompt'            => $prompt,
				'style'             => $style,
				'colors'            => $colors,
				'remove_background' => $remove_bg,
				'user_id'           => self::user_key( $user_id ),
			)
		);
		if ( is_wp_error( $result ) ) {
			self::fail( $result );
		}
		$job_id = isset( $result['job_id'] ) ? (string) $result['job_id'] : '';
		if ( ! preg_match( '/^[a-f0-9]{32}$/', $job_id ) ) {
			wp_send_json_error( array( 'message' => 'Réponse inattendue du service de création.' ), 502 );
		}

		++$usage['count'];
		update_user_meta( $user_id, 'tsia_usage', $usage );

		$jobs = get_user_meta( $user_id, 'tsia_jobs', true );
		$jobs = is_array( $jobs ) ? $jobs : array();
		$jobs[ $job_id ] = array(
			'prompt'  => $prompt,
			'style'   => $style,
			'colors'  => $colors,
			'created' => time(),
		);
		$jobs = array_slice( $jobs, -self::MAX_JOBS, null, true );
		update_user_meta( $user_id, 'tsia_jobs', $jobs );

		wp_send_json_success(
			array(
				'job_id'    => $job_id,
				'status'    => $result['status'] ?? 'queued',
				'position'  => $result['position'] ?? null,
				'remaining' => $quota > 0 ? $quota - $usage['count'] : null,
			)
		);
	}

	public static function status() {
		check_ajax_referer( 'tsia_designer', 'nonce' );
		$user_id = get_current_user_id();
		$job_id  = isset( $_GET['job_id'] ) ? sanitize_key( wp_unslash( $_GET['job_id'] ) ) : '';

		$jobs = get_user_meta( $user_id, 'tsia_jobs', true );
		if ( ! preg_match( '/^[a-f0-9]{32}$/', $job_id ) || ! is_array( $jobs ) || ! isset( $jobs[ $job_id ] ) ) {
			wp_send_json_error( array( 'message' => 'Design introuvable.' ), 404 );
		}

		// Déjà rapatrié sur le site : pas besoin de réinterroger le service.
		if ( ! empty( $jobs[ $job_id ]['files'] ) ) {
			wp_send_json_success( self::done_payload( $job_id, $jobs[ $job_id ] ) );
		}

		$user_key = self::user_key( $user_id );
		$result   = TSIA_Client::job_status( $job_id, $user_key );
		if ( is_wp_error( $result ) ) {
			self::fail( $result );
		}

		$status = $result['status'] ?? 'error';
		if ( 'done' !== $status ) {
			wp_send_json_success(
				array(
					'job_id'   => $job_id,
					'status'   => $status,
					'position' => $result['position'] ?? null,
					'error'    => 'error' === $status ? ( $result['error'] ?? 'La création a échoué.' ) : null,
				)
			);
		}

		$files = self::store_files( $job_id, $user_key );
		if ( is_wp_error( $files ) ) {
			self::fail( $files );
		}
		$jobs[ $job_id ]['files']  = $files;
		$jobs[ $job_id ]['result'] = self::sanitize_result( $result['result'] ?? array() );
		update_user_meta( $user_id, 'tsia_jobs', $jobs );

		wp_send_json_success( self::done_payload( $job_id, $jobs[ $job_id ] ) );
	}

	private static function done_payload( $job_id, array $job ) {
		return array(
			'job_id' => $job_id,
			'status' => 'done',
			'files'  => $job['files'],
			'result' => $job['result'],
		);
	}

	private static function sanitize_result( $result ) {
		$result  = is_array( $result ) ? $result : array();
		$palette = array();
		foreach ( (array) ( $result['palette'] ?? array() ) as $ink ) {
			$hex = sanitize_hex_color( $ink['hex'] ?? '' );
			if ( $hex ) {
				$palette[] = array( 'hex' => $hex, 'share' => (float) ( $ink['share'] ?? 0 ) );
			}
		}
		return array(
			'palette'  => $palette,
			'inks'     => count( $palette ),
			'paths'    => absint( $result['stats']['paths'] ?? 0 ),
			'warnings' => array_map( 'sanitize_text_field', (array) ( $result['warnings'] ?? array() ) ),
		);
	}

	/** Le SVG est produit par vtracer, mais on le contrôle quand même avant de le publier. */
	private static function is_safe_svg( $svg ) {
		if ( ! preg_match( '/^\s*(<\?xml[^>]*\?>\s*)?(<!--.*?-->\s*)*<svg[\s>]/s', $svg ) ) {
			return false;
		}
		return ! preg_match( '/<script|<foreignObject|javascript:|\son[a-z]+\s*=|<!ENTITY|xlink:href\s*=\s*["\']\s*(?!#)/i', $svg );
	}

	private static function store_files( $job_id, $user_key ) {
		$svg = TSIA_Client::job_file( $job_id, $user_key, 'design.svg' );
		if ( is_wp_error( $svg ) ) {
			return $svg;
		}
		$png = TSIA_Client::job_file( $job_id, $user_key, 'source.png' );
		if ( is_wp_error( $png ) ) {
			return $png;
		}
		if ( ! self::is_safe_svg( $svg ) || 0 !== strpos( $png, "\x89PNG" ) ) {
			return new WP_Error( 'tsia_invalid_file', 'Le fichier produit n\'a pas passé le contrôle de sécurité.', array( 'status' => 502 ) );
		}

		$uploads = wp_upload_dir();
		if ( ! empty( $uploads['error'] ) ) {
			return new WP_Error( 'tsia_uploads', 'Impossible d\'enregistrer le design sur le site.', array( 'status' => 500 ) );
		}
		$subdir = 'tsia/' . gmdate( 'Y/m' );
		$dir    = trailingslashit( $uploads['basedir'] ) . $subdir;
		if ( ! wp_mkdir_p( $dir ) ) {
			return new WP_Error( 'tsia_uploads', 'Impossible d\'enregistrer le design sur le site.', array( 'status' => 500 ) );
		}
		$guard = trailingslashit( $uploads['basedir'] ) . 'tsia/index.php';
		if ( ! file_exists( $guard ) ) {
			file_put_contents( $guard, "<?php\n// Silence.\n" ); // phpcs:ignore WordPress.WP.AlternativeFunctions
		}

		// L'identifiant aléatoire de 32 caractères rend l'adresse des fichiers impossible à deviner.
		file_put_contents( $dir . '/' . $job_id . '.svg', $svg ); // phpcs:ignore WordPress.WP.AlternativeFunctions
		file_put_contents( $dir . '/' . $job_id . '.png', $png ); // phpcs:ignore WordPress.WP.AlternativeFunctions

		$base_url = trailingslashit( $uploads['baseurl'] ) . $subdir . '/' . $job_id;
		return array(
			'svg' => $base_url . '.svg',
			'png' => $base_url . '.png',
		);
	}
}
