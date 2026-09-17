<?php
if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/**
 * Appels serveur à serveur vers le microservice. La clé API ne quitte jamais WordPress.
 */
class TSIA_Client {

	private static function request( $method, $path, $body = null, $raw = false ) {
		$base = rtrim( (string) TSIA_Settings::get( 'service_url' ), '/' );
		$key  = (string) TSIA_Settings::get( 'api_key' );
		if ( '' === $base || '' === $key ) {
			return new WP_Error( 'tsia_not_configured', 'Le service de création n\'est pas encore configuré.', array( 'status' => 503 ) );
		}

		$args = array(
			'method'  => $method,
			'timeout' => 20,
			'headers' => array(
				'X-API-Key' => $key,
				'Accept'    => $raw ? '*/*' : 'application/json',
			),
		);
		if ( null !== $body ) {
			$args['headers']['Content-Type'] = 'application/json';
			$args['body']                    = wp_json_encode( $body );
		}

		$response = wp_remote_request( $base . $path, $args );
		if ( is_wp_error( $response ) ) {
			return new WP_Error( 'tsia_unreachable', 'Le service de création est injoignable. Réessayez dans quelques minutes.', array( 'status' => 503 ) );
		}

		$code    = (int) wp_remote_retrieve_response_code( $response );
		$content = wp_remote_retrieve_body( $response );

		if ( $code >= 400 ) {
			$data    = json_decode( $content, true );
			$message = ( is_array( $data ) && isset( $data['detail'] ) && is_string( $data['detail'] ) )
				? $data['detail']
				: 'La demande a été refusée par le service de création.';
			if ( 401 === $code ) {
				// Problème de configuration : inutile d'exposer le détail au client.
				$message = 'Le service de création est mal configuré. Prévenez l\'équipe du site.';
			}
			return new WP_Error( 'tsia_http_' . $code, $message, array( 'status' => $code ) );
		}

		if ( $raw ) {
			return $content;
		}
		$data = json_decode( $content, true );
		if ( ! is_array( $data ) ) {
			return new WP_Error( 'tsia_bad_response', 'Réponse inattendue du service de création.', array( 'status' => 502 ) );
		}
		return $data;
	}

	public static function start_job( array $payload ) {
		return self::request( 'POST', '/generate', $payload );
	}

	public static function job_status( $job_id, $user_key ) {
		return self::request( 'GET', '/jobs/' . rawurlencode( $job_id ) . '?user_id=' . rawurlencode( $user_key ) );
	}

	public static function job_file( $job_id, $user_key, $filename ) {
		return self::request(
			'GET',
			'/jobs/' . rawurlencode( $job_id ) . '/' . rawurlencode( $filename ) . '?user_id=' . rawurlencode( $user_key ),
			null,
			true
		);
	}
}
