// Calls STS through the AWS SDK for Java 2.x with no endpoint or credentials in code.
import software.amazon.awssdk.services.sts.StsClient;

public class Check {
    public static void main(String[] args) {
        try (StsClient sts = StsClient.create()) {
            String account = sts.getCallerIdentity().account();
            System.out.println("account " + account);
            System.exit("000000000000".equals(account) ? 0 : 1);
        } catch (RuntimeException e) {
            for (Throwable t = e; t != null; t = t.getCause()) {
                System.out.println(t.getClass().getName() + ": " + t.getMessage());
            }
            System.exit(1);
        }
    }
}
